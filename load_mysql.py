import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

# ====== Tetapan sambungan MySQL (XAMPP) ======
DB_USER = "root"
DB_PASS = ""          # kosong kalau kau tak pernah letak password (default XAMPP)
DB_HOST = "localhost"
DB_PORT = 3306
DB_NAME = "pricecatcher"
# =============================================

url = URL.create(
    "mysql+pymysql",
    username=DB_USER,
    password=DB_PASS or None,
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
    query={"charset": "utf8mb4"},
)
engine = create_engine(url)

print("Membaca fail CSV...")
item = pd.read_csv("item_selected.csv")
premise = pd.read_csv("premise.csv")
prices = pd.read_csv("prices_filtered.csv", parse_dates=["date"])
prices["price"] = prices["price"].round(2)

print("Mencipta jadual...")
with engine.begin() as conn:
    conn.execute(text("DROP TABLE IF EXISTS prices"))
    conn.execute(text("DROP TABLE IF EXISTS item"))
    conn.execute(text("DROP TABLE IF EXISTS premise"))

    conn.execute(text("""
        CREATE TABLE item (
            item_code INT PRIMARY KEY,
            item VARCHAR(255),
            unit VARCHAR(50),
            item_group VARCHAR(100),
            item_category VARCHAR(100)
        ) CHARACTER SET utf8mb4
    """))
    conn.execute(text("""
        CREATE TABLE premise (
            premise_code INT PRIMARY KEY,
            premise VARCHAR(255),
            address TEXT,
            premise_type VARCHAR(100),
            state VARCHAR(100),
            district VARCHAR(100)
        ) CHARACTER SET utf8mb4
    """))
    conn.execute(text("""
        CREATE TABLE prices (
            price_id INT AUTO_INCREMENT PRIMARY KEY,
            `date` DATE NOT NULL,
            premise_code INT NOT NULL,
            item_code INT NOT NULL,
            price DECIMAL(8,2) NOT NULL
        ) CHARACTER SET utf8mb4
    """))

print("Memasukkan data (ambil sedikit masa)...")
item.to_sql("item", engine, if_exists="append", index=False)
premise.to_sql("premise", engine, if_exists="append", index=False, chunksize=2000, method="multi")
prices.to_sql("prices", engine, if_exists="append", index=False, chunksize=5000, method="multi")

print("Membuat index...")
with engine.begin() as conn:
    conn.execute(text("CREATE INDEX idx_prices_item_date ON prices (item_code, `date`)"))
    conn.execute(text("CREATE INDEX idx_prices_premise ON prices (premise_code)"))

print("\n===== Semakan =====")
with engine.connect() as conn:
    for t in ["item", "premise", "prices"]:
        n = conn.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
        print(f"{t}: {n} baris")
    orphan = conn.execute(text("""
        SELECT COUNT(*) FROM prices p
        LEFT JOIN premise pr ON p.premise_code = pr.premise_code
        WHERE pr.premise_code IS NULL
    """)).scalar()
    print("Rekod harga tanpa padanan premis:", orphan)

print("\nSiap. Buka phpMyAdmin dan semak database 'pricecatcher'.")
