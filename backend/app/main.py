from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import engine, Base
from app.routers import auth, users, stores, sync, products, reports, zra_digitax, purchases

# Initialize PostgreSQL tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Beleka POS Cloud PostgreSQL API",
    description="Multi-Store Cloud Database API Service for Beleka Point of Sale System",
    version="1.0.0",
)

# Enable CORS for POS terminals & Web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(stores.router)
app.include_router(sync.router)
app.include_router(products.router)
app.include_router(reports.router)
app.include_router(zra_digitax.router)
app.include_router(purchases.router)

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
