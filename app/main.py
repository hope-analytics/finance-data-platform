import os
from dotenv import load_dotenv
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import Optional
from pydantic import BaseModel, Field

load_dotenv("/Users/hopey/household-expenses/.env")
from psycopg2 import connect
from psycopg2.extras import RealDictCursor


# ---------------------------------
# Configuration
# ---------------------------------

DATABASE_URL = f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
APP_USERNAME = os.getenv("APP_USERNAME")
APP_PASSWORD = os.getenv("APP_PASSWORD")
API_TOKEN = os.getenv("API_TOKEN")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not configured")

if not APP_USERNAME or not APP_PASSWORD:
    raise RuntimeError("APP_USERNAME and APP_PASSWORD are not configured")

if not API_TOKEN:
    raise RuntimeError("API_TOKEN is not configured")


# ---------------------------------
# Application setup
# ---------------------------------

app = FastAPI(
    title="Finance Data Platform API",
    description="API for capturing and retrieving household financial transactions.",
    version="1.0.0",
)

app.mount("/static", StaticFiles(directory="static"), name="static")

templates = Jinja2Templates(directory="templates")

basic_auth = HTTPBasic()
bearer_auth = HTTPBearer()


# ---------------------------------
# Database
# ---------------------------------

def get_connection():
    return connect(DATABASE_URL)


# ---------------------------------
# Models
# ---------------------------------

class ExpenseCreate(BaseModel):
    transaction_date: date
    merchant: str = Field(..., min_length=1, max_length=150)
    description: Optional[str] = None
    amount: Decimal = Field(..., gt=0)
    category: Optional[str] = None
    payment_source_id: int
    notes: Optional[str] = None
    installment_count: Optional[int] = Field(default=None, ge=2)

    owner_id: int = Field(..., gt=0)
    participant_ids: list[int] = Field(default_factory=list)

# ---------------------------------
# Authentication
# ---------------------------------

def verify_basic_auth(
    credentials: HTTPBasicCredentials = Depends(basic_auth),
):
    if (
        credentials.username != APP_USERNAME
        or credentials.password != APP_PASSWORD
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )

    return credentials.username


def verify_bearer_token(
    credentials=Depends(bearer_auth),
):
    if credentials.credentials != API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API token",
        )

    return True


# ---------------------------------
# Helpers
# ---------------------------------

def fetch_expenses():
    query = """
        SELECT
            t.expense_id,
            t.transaction_date,
            t.merchant,
            t.description,
            t.amount,
            t.category,
            t.payment_source_id,
            ps.payment_name,
            t.notes,
            t.created_at
        FROM transactions AS t
        JOIN payment_sources AS ps
            ON ps.payment_source_id = t.payment_source_id
        WHERE obligation_type <> 'RECURRING'
        ORDER BY t.transaction_date DESC, t.expense_id DESC
        LIMIT 10
    """

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query)
            return cursor.fetchall()


def fetch_payment_sources():
    query = """
        SELECT
            payment_source_id,
            payment_name,
            payment_type
        FROM payment_sources
        WHERE active = TRUE
        ORDER BY payment_source_id
    """

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query)
            return cursor.fetchall()

def fetch_categories():
    query = """
        SELECT
            category_id,
            category_name
        FROM transactions_category
        ORDER BY category_id
    """

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query)
            return cursor.fetchall()

def fetch_people():
    query = """
        SELECT
            person_id,
            name
        FROM people
        ORDER BY name, person_id
    """

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query)
            return cursor.fetchall()

def create_expense(expense: ExpenseCreate):
    if len(expense.participant_ids) != len(set(expense.participant_ids)):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Participant IDs must not contain duplicates.",
        )

    if any(person_id <= 0 for person_id in expense.participant_ids):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Participant IDs must be positive integers.",
        )

    insert_query = """
        INSERT INTO transactions (
            transaction_date,
            merchant,
            description,
            amount,
            category,
            payment_source_id,
            notes,
            obligation_type,
            owner_id
        )
        SELECT
            %s,
            %s,
            %s,
            %s,
            %s,
            ps.payment_source_id,
            %s,
            CASE
                WHEN ps.payment_type = 'CREDIT_CARD'
                     AND %s IS NOT NULL
                    THEN 'INSTALLMENT'
                WHEN ps.payment_type = 'CREDIT_CARD'
                    THEN 'SINGLE_PAYMENT'
                ELSE 'NORMAL'
            END,
            %s
        FROM payment_sources AS ps
        WHERE ps.payment_source_id = %s
          AND ps.active = TRUE
        RETURNING
            expense_id,
            transaction_date,
            merchant,
            description,
            amount,
            category,
            payment_source_id,
            notes,
            obligation_type,
            owner_id,
            participant_ids,
            created_at
    """

    with get_connection() as conn:
        try:
            with conn.cursor(
                cursor_factory=RealDictCursor
            ) as cursor:

                # Validate owner against the reference table.
                cursor.execute(
                    """
                    SELECT 1
                    FROM people
                    WHERE person_id = %s
                    """,
                    (expense.owner_id,),
                )

                if cursor.fetchone() is None:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="The selected owner does not exist.",
                    )

                # Validate participant IDs before insertion.
                if expense.participant_ids:
                    cursor.execute(
                        """
                        SELECT person_id
                        FROM people
                        WHERE person_id = ANY(%s::BIGINT[])
                        """,
                        (expense.participant_ids,),
                    )

                    valid_ids = {
                        row["person_id"]
                        for row in cursor.fetchall()
                    }

                    invalid_ids = (
                        set(expense.participant_ids) - valid_ids
                    )

                    if invalid_ids:
                        raise HTTPException(
                            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail=(
                                "One or more selected participants "
                                "do not exist."
                            ),
                        )

                cursor.execute(
                    insert_query,
                    (
                        expense.transaction_date,
                        expense.merchant,
                        expense.description,
                        expense.amount,
                        expense.category,
                        expense.notes,
                        expense.installment_count,
                        expense.owner_id,
                        expense.payment_source_id,
                    ),
                )

                result = cursor.fetchone()

                if result is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid or inactive payment source.",
                    )

                result = dict(result)
                expense_id = result["expense_id"]

                # Database function is the sole participant
                # membership assignment mechanism.
                cursor.execute(
                    """
                    SELECT set_transaction_participants(
                        %s::BIGINT,
                        %s::BIGINT[]
                    )
                    """,
                    (
                        expense_id,
                        expense.participant_ids,
                    ),
                )

                # Preserve existing installment creation behavior.
                if expense.installment_count is not None:
                    cursor.execute(
                        """
                        SELECT create_installment_plan(
                            %s::BIGINT,
                            %s::SMALLINT
                        ) AS plan_id
                        """,
                        (
                            expense_id,
                            expense.installment_count,
                        ),
                    )

                    installment_result = cursor.fetchone()
                    result["installment_plan_id"] = (
                        installment_result["plan_id"]
                    )

                # Read back authoritative participant membership.
                cursor.execute(
                    """
                    SELECT participant_ids
                    FROM transactions
                    WHERE expense_id = %s
                    """,
                    (expense_id,),
                )

                result["participant_ids"] = (
                    cursor.fetchone()["participant_ids"]
                )

            conn.commit()
            return result

        except HTTPException:
            conn.rollback()
            raise

        except Exception:
            conn.rollback()
            raise

# ---------------------------------
# Security headers
# ---------------------------------

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)

    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

    return response


# ---------------------------------
# API routes
# ---------------------------------

@app.get("/expenses")
def get_expenses(
    _: bool = Depends(verify_bearer_token),
):
    return fetch_expenses()


@app.post("/expenses", status_code=status.HTTP_201_CREATED)
def post_expense(
    expense: ExpenseCreate,
    _: bool = Depends(verify_bearer_token),
):
    return create_expense(expense)


# ---------------------------------
# Web application routes
# ---------------------------------

@app.get("/app", response_class=HTMLResponse)
def app_home(
    request: Request,
    _: str = Depends(verify_basic_auth),
):
    return templates.TemplateResponse(
        request=request,
        name="index.html",
        context={},
    )


@app.get("/app/expenses")
def app_expenses(
    _: str = Depends(verify_basic_auth),
):
    return fetch_expenses()


@app.post("/app/expenses")
def app_create_expense(
    expense: ExpenseCreate,
    _: str = Depends(verify_basic_auth),
):
    return create_expense(expense)


@app.get("/app/payment-sources")
def app_payment_sources(
    _: str = Depends(verify_basic_auth),
):
    return fetch_payment_sources()

@app.get("/app/categories")
def app_categories(
    _: str = Depends(verify_basic_auth),
):
    return fetch_categories()

@app.get("/app/people")
def app_people(
    _: str = Depends(verify_basic_auth),
):
    return fetch_people()

# ---------------------------------
# Health check
# ---------------------------------

@app.get("/health")
def health_check():
    return {"status": "ok"}
