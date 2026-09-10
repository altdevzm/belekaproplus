from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base, seed_initial_data
from app.routers import auth, users, stores, sync, products, reports, zra_digitax, purchases, tot, tax_statement

# Initialize PostgreSQL tables. Account and branch creation must be explicit.
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Beleka POS Cloud PostgreSQL API",
    description="Multi-Store Cloud Database API Service for Beleka Point of Sale System",
    version="2.6.0",

)

# Secure CORS middleware configuration
import os
allowed_origins_env = os.getenv("ALLOWED_ORIGINS", "*")
allowed_origins = [o.strip() for o in allowed_origins_env.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if "*" not in allowed_origins else ["*"],
    allow_credentials=False if "*" in allowed_origins else True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-API-Key"],
)


app.include_router(auth.router)
app.include_router(users.router)
app.include_router(stores.router)
app.include_router(sync.router)
app.include_router(products.router)
app.include_router(reports.router)
app.include_router(zra_digitax.router)
app.include_router(purchases.router)
app.include_router(tot.router)
app.include_router(tax_statement.router)

@app.get("/")
def root():
    return {
        "status": "online",
        "service": "Beleka POS Multi-Store Cloud Database Service",
        "database": "PostgreSQL Cloud DB"
    }

@app.get("/health")
def health_check():
    return {"status": "healthy"}
