import pandas as pd

BASE = "https://storage.data.gov.my/pricecatcher/"

# Item yang dipilih untuk projek ni
ITEMS = {
    1: "AYAM BERSIH - STANDARD (1kg)",
    1109: "TELUR AYAM GRED A (30 biji)",
    267: "MINYAK MASAK TULEN CAP VESAWIT (1kg)",
}

# 12 bulan penuh: Julai 2025 hingga Jun 2026
months = pd.period_range("2025-07", "2026-06", freq="M")

frames = []
for m in months:
    label = m.strftime("%Y-%m")
    url = f"{BASE}pricecatcher_{label}.parquet"
    try:
        df = pd.read_parquet(url)
    except Exception as e:
        print(f"{label}: GAGAL ({type(e).__name__}) - dilangkau")
        continue
    df = df[df["item_code"].isin(list(ITEMS.keys()))]
    print(f"{label}: {len(df)} rekod dipilih")
    frames.append(df)

if not frames:
    raise SystemExit("Tiada data berjaya di-download. Semak sambungan internet.")

prices = pd.concat(frames, ignore_index=True)
prices["date"] = pd.to_datetime(prices["date"])

item = pd.read_parquet(BASE + "lookup_item.parquet")
premise = pd.read_parquet(BASE + "lookup_premise.parquet")

prices.to_csv("prices_filtered.csv", index=False)
item[item["item_code"].isin(list(ITEMS.keys()))].to_csv(
    "item_selected.csv", index=False, encoding="utf-8-sig"
)
premise.to_csv("premise.csv", index=False, encoding="utf-8-sig")

print("\n===== Ringkasan =====")
print("Jumlah rekod:", len(prices))
print("Julat tarikh:", prices["date"].min().date(), "hingga", prices["date"].max().date())
print("\nRekod ikut item_code:")
print(prices["item_code"].value_counts().sort_index())
print("\nSiap. Fail disimpan: prices_filtered.csv, item_selected.csv, premise.csv")
