import os
import secrets

from datetime import date
from decimal import Decimal

from dotenv import load_dotenv
from fastapi import FastAPI, Request, HTTPException, Header, status, Depends
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from starlette.middleware.base import BaseHTTPMiddleware

from pydantic import BaseModel, Field

from app.database import get_connection


# --------------------------------------------------
# Configuration
# --------------------------------------------------

load_dotenv()

API_TOKEN = os.getenv("API_TOKEN")

if not API_TOKEN:
    raise RuntimeError("API_TOKEN is not configured")

APP_USERNAME = os.getenv("APP_USERNAME")
APP_PASSWORD = os.getenv("APP_PASSWORD")

security = HTTPBasic()
def authenticate(
    credentials: HTTPBasicCredentials = Depends(security),
):
    if not APP_USERNAME or not APP_PASSWORD:
        raise RuntimeError("APP_USERNAME and APP_PASSWORD must be configured")

    username_correct = secrets.compare_digest(
        credentials.username,
        APP_USERNAME,
    )

    password_correct = secrets.compare_digest(
        credentials.password,
        APP_PASSWORD,
    )

    if not (username_correct and password_correct):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
            headers={"WWW-Authenticate": "Basic"},
        )

    return credentials.username


# --------------------------------------------------
# FastAPI
# --------------------------------------------------

app = FastAPI(
    title="Household Expenses",
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = (
            "camera=(), microphone=(), geolocation=()"
        )

        return response


app.add_middleware(SecurityHeadersMiddleware)

app.mount(
    "/static",
    StaticFiles(directory="static"),
    name="static"
)

templates = Jinja2Templates(
    directory="templates"
)


# --------------------------------------------------
# Authentication
# --------------------------------------------------

def verify_api_token(
    authorization: str | None = Header(default=None)
):
    expected = f"Bearer {API_TOKEN}"

    if authorization != expected:
        raise HTTPException(
            status_code=401,
            detail="Unauthorized"
        )


# --------------------------------------------------
# GUI
# --------------------------------------------------

@app.get("/app")
def expense_app(
    request: Request,
    username: str = Depends(authenticate)):
    return templates.TemplateResponse(
        request=request,
        name="index.html"
    )


# --------------------------------------------------
# Expense model
# --------------------------------------------------

class ExpenseCreate(BaseModel):
    transaction_date: date
    merchant: str = Field(
        min_length=1,
        max_length=150
    )
    description: str | None = None
    amount: Decimal = Field(gt=0)
    category: str | None = None
    payment_source: str = Field(
        min_length=1,
        max_length=50
    )
    notes: str | None = None


# --------------------------------------------------
# Get expenses
# --------------------------------------------------

@app.get("/expenses")
def get_expenses(
    username: str = Depends(authenticate)
):
    with get_connection() as conn:
        with conn.cursor() as cur:

            cur.execute(
                """
                SELECT
                    expense_id,
                    transaction_date,
                    merchant,
                    description,
                    amount,
                    category,
                    payment_source,
                    notes,
                    created_at
                FROM transactions
                ORDER BY
                    transaction_date DESC,
                    expense_id DESC;
                """
            )

            rows = cur.fetchall()

            columns = [
                "expense_id",
                "transaction_date",
                "merchant",
                "description",
                "amount",
                "category",
                "payment_source",
                "notes",
                "created_at",
            ]

            return [
                dict(zip(columns, row))
                for row in rows
            ]


# --------------------------------------------------
# Create expense
# --------------------------------------------------

@app.post("/expenses")
def create_expense(
    expense: ExpenseCreate,
    username: str = Depends(authenticate)
):
    with get_connection() as conn:
        with conn.cursor() as cur:

            cur.execute(
                """
                INSERT INTO transactions (
                    transaction_date,
                    merchant,
                    description,
                    amount,
                    category,
                    payment_source,
                    notes
                )
                VALUES (
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s,
                    %s
                )
                RETURNING expense_id;
                """,
                (
                    expense.transaction_date,
                    expense.merchant,
                    expense.description,
                    expense.amount,
                    expense.category,
                    expense.payment_source,
                    expense.notes,
                ),
            )

            expense_id = cur.fetchone()[0]

        conn.commit()

    return {
        "message": "Expense created successfully",
        "expense_id": expense_id,
    }

# --------------------------------------------------
# GUI expense routes
# --------------------------------------------------

@app.get("/app/expenses")
def get_app_expenses():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    expense_id,
                    transaction_date,
                    merchant,
                    description,
                    amount,
                    category,
                    payment_source,
                    notes,
                    created_at
                FROM transactions
                ORDER BY
                    transaction_date DESC,
                    expense_id DESC;
                """
            )

            rows = cur.fetchall()

            columns = [
                "expense_id",
                "transaction_date",
                "merchant",
                "description",
                "amount",
                "category",
                "payment_source",
                "notes",
                "created_at",
            ]

            return [
                dict(zip(columns, row))
                for row in rows
            ]


@app.post("/app/expenses")
def create_app_expense(expense: ExpenseCreate):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO transactions (
                    transaction_date,
                    merchant,
                    description,
                    amount,
                    category,
                    payment_source,
                    notes
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s
                )
                RETURNING expense_id;
                """,
                (
                    expense.transaction_date,
                    expense.merchant,
                    expense.description,
                    expense.amount,
                    expense.category,
                    expense.payment_source,
                    expense.notes,
                ),
            )

            expense_id = cur.fetchone()[0]

        conn.commit()

    return {
        "message": "Expense created successfully",
        "expense_id": expense_id,
    }