import os
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field
from psycopg2 import connect
from psycopg2.extras import RealDictCursor


# ---------------------------------
# Configuration
# ---------------------------------

DATABASE_URL = os.getenv("DATABASE_URL")
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
        ORDER BY t.transaction_date DESC, t.expense_id DESC
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


def create_expense(expense: ExpenseCreate):
    query = """
        INSERT INTO transactions (
            transaction_date,
            merchant,
            description,
            amount,
            category,
            payment_source_id,
            notes
        )
        SELECT
            %s,
            %s,
            %s,
            %s,
            %s,
            ps.payment_source_id,
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
            created_at
    """

    values = (
        expense.transaction_date,
        expense.merchant,
        expense.description,
        expense.amount,
        expense.category,
        expense.notes,
        expense.payment_source_id,
    )

    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, values)

            result = cursor.fetchone()

            if result is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid or inactive payment source",
                )

            conn.commit()

            return result


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


# ---------------------------------
# Health check
# ---------------------------------

@app.get("/health")
def health_check():
    return {"status": "ok"}
