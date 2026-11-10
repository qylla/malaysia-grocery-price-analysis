# Malaysia Grocery Price Trends: Chicken, Eggs and Cooking Oil

Analysis of KPDN PriceCatcher retail price data, **July 2025 – June 2026**.

**Tools:** Python (pandas) · MySQL · SQL (joins, aggregation, self-joins) · phpMyAdmin

## Summary

I set out to answer two business questions with open government data:

1. **Which state is the most expensive?**
   East Malaysia, by a wide margin, for chicken and eggs. Chicken in Sabah averages **RM12.72/kg vs RM8.34 in Johor (over 50% higher)**, and a tray of 30 Grade A eggs in Sarawak averages **RM16.79 vs RM12.99 in Johor (29% higher)**. Within Peninsular Malaysia the states are close together. Cooking oil (Vesawit 1kg) costs about the same everywhere (RM6.86–6.92).
2. **When do prices jump?**
   Using a same-store comparison and a 5% monthly threshold, I found four sudden increases, all in Peninsular Malaysia: **eggs in Sep 2025 (+11.1%), Dec 2025 (+8.2%) and Jun 2026 (+8.8%), and chicken in Jun 2026 (+6.9%)**. Eggs and chicken both rose in June 2026. Cooking oil never moved more than 0.52% in a month.

Two checks make these results more trustworthy: the East–West gap persists **within every store type** (it is not a store-mix effect), and the jumps persist when only the **same stores** are compared month to month (they are not a reporting artefact).

## Business questions

- Which state is the most expensive for everyday staples?
- When do prices rise suddenly?

## Data

| Item | Detail |
|---|---|
| Source | KPDN PriceCatcher via [OpenDOSM / data.gov.my](https://open.dosm.gov.my/data-catalogue/pricecatcher) |
| Licence | CC BY 4.0 |
| Period | 1 Jul 2025 – 30 Jun 2026 (12 monthly Parquet files) |
| Downloaded | 9 Nov 2026 |
| Raw size | About 2.3 million price records per month (Jul 2025: 2,323,499) |
| Tables | Daily prices (`date`, `premise_code`, `item_code`, `price`) joined to lookup tables for items and premises (name, type, state, district) |

To keep the analysis focused, I selected three items sold in a single, comparable pack size:

| Item | Code | Records |
|---|---|---|
| Ayam Bersih – Standard (1kg) | 1 | 286,082 |
| Telur Ayam Gred A (30 eggs) | 1109 | 200,934 |
| Minyak Masak Tulen Cap Vesawit (1kg) | 267 | 30,849 |

That gives **517,865 records** across 3,932 premises.

I chose 30-egg packs because they have far more records than the 10-egg packs, and I did not mix pack sizes within an item.

## Method

1. **Download and filter (Python).** Read the monthly Parquet files, keep the three items, and save to CSV (`scripts/download_data.py`).
2. **Load into MySQL.** Create `item`, `premise` and `prices` tables with keys and indexes (`scripts/load_mysql.py`). Every price row matched a premise.
3. **Clean.** I inspected the price distribution of each item and set ranges where the data clearly stops looking like real prices (`queries.sql`, sections 2–4):

   | Item | Kept range | Rows removed |
   |---|---|---|
   | Chicken | RM5 – RM15 | 67 |
   | Eggs (30) | RM9 – RM25 | 61 |
   | Cooking oil | RM5 – RM9 | 14 |

   In total **142 of 517,865 rows (0.03%)** were removed. Examples of what was removed: eggs at RM1,500 and RM135, chicken at RM111 and RM0.70, and cooking oil at RM30.90 (which looks like a 5kg price keyed in as 1kg). The raw table is untouched.

   High egg prices (RM17+) were **kept**: 3,344 records, almost all in Sabah, Sarawak and W.P. Labuan, with plausible maximums (RM20–22). They are real regional prices, not errors.
4. **Define zones.** East Malaysia (Sabah, Sarawak, W.P. Labuan) versus Peninsular Malaysia, because price levels differ sharply between the two.
5. **Monthly summaries.** Average price by item, zone and month (`monthly_prices`).
6. **Same-store comparison.** For each month-to-month change, compare only the stores that reported in both months (`premise_monthly`). This removes the effect of different stores reporting in different months.
7. **Definition of a "sudden increase":** a rise of **5% or more** in one month, in the same-store average, with at least **30** matched stores.

## Findings

### 1. Average price by state (cleaned data)

| State | Chicken (RM/kg) | Eggs (RM/30) | Cooking oil (RM/kg) |
|---|---|---|---|
| W.P. Labuan* | 12.52 | 18.48 | 6.90 |
| Sabah | **12.72** | 16.05 | 6.90 |
| Sarawak | 10.68 | **16.79** | 6.90 |
| Pulau Pinang | 9.11 | 13.63 | 6.89 |
| Perlis | 9.03 | 13.18 | 6.90* |
| Terengganu | 8.88 | 13.56 | 6.89 |
| Kedah | 8.79 | 13.16 | 6.88 |
| W.P. Kuala Lumpur | 8.79 | 13.30 | 6.89 |
| Perak | 8.73 | 13.10 | 6.86 |
| Selangor | 8.72 | 13.25 | 6.89 |
| Pahang | 8.69 | 13.21 | 6.87 |
| Melaka | 8.65 | 13.13 | 6.89 |
| Negeri Sembilan | 8.64 | 13.22 | 6.88 |
| W.P. Putrajaya | 8.64 | 13.32 | 6.92 |
| Kelantan | 8.56 | 13.43 | 6.87 |
| Johor | **8.34** | **12.99** | 6.89 |

\* Small samples: W.P. Labuan has only 4 (chicken), 8 (eggs) and 6 (oil) reporting stores; Perlis has 7 oil stores.

- Peninsular states span only RM0.77 for chicken and RM0.64 for eggs.
- Chicken in Sabah is over 50% above Johor, and in Sarawak 28% above. Eggs in Sarawak are 29% above Johor, and in Sabah 24% above.
- Cleaning barely changed the state averages (chicken moved by at most RM0.02).

### 2. The East–West gap is not explained by store type

Average price within the same premise type (RM; chicken per kg, eggs per 30):

| Premise type | Chicken: Peninsular → East | Gap | Eggs: Peninsular → East | Gap |
|---|---|---|---|---|
| Hypermarket | 7.89 → 11.67 | +48% | 13.09 → 16.17 | +24% |
| Supermarket / Pasar Raya | 8.25 → 11.39 | +38% | 13.08 → 16.03 | +23% |
| Wet market (Pasar Basah) | 9.91 → 11.83 | +19% | 13.81 → 17.57 | +27% |
| Mini market (Pasar Mini) | 8.89 → 10.60 | +19% | 13.42 → 16.02 | +19% |
| Convenience store (Kedai Runcit)* | 9.18 → 11.27 | +23% | 13.63 → 17.83 | +31% |

\* Only 7 stores (56 records) in East Malaysia for chicken, so treat with caution. Wholesale (Borong) has no East Malaysian data.

East Malaysia is more expensive in every store type, so the gap reflects location, not a different mix of shops. The causes (logistics, local supply, policy) are not tested here.

Within Peninsular Malaysia, chicken at wet markets (RM9.91) is about 20–26% dearer than at supermarkets or hypermarkets. For eggs the difference is about 6%.

### 3. Sudden price increases

Same-store monthly changes at or above 5%, with the matching drops for context. All are Peninsular Malaysia.

| Item | Month | Matched stores | Previous avg | This month | Change |
|---|---|---|---|---|---|
| Eggs | Sep 2025 | 972 | 12.90 | 14.33 | **+11.08%** |
| Eggs | Nov 2025 | 993 | 14.23 | 13.01 | −8.58% |
| Eggs | Dec 2025 | 992 | 13.02 | 14.09 | **+8.20%** |
| Eggs | Apr 2026 | 1,010 | 13.62 | 12.47 | −8.43% |
| Eggs | Jun 2026 | 1,015 | 12.39 | 13.48 | **+8.79%** |
| Chicken | Mar 2026 | 1,089 | 9.44 | 8.76 | −7.26% |
| Chicken | Jun 2026 | 1,093 | 8.78 | 9.39 | **+6.88%** |

- **Same-store changes are nearly identical to the all-store averages** (for example eggs in Sep 2025: +11.15% vs +11.08%). The jumps are real price movements, not an artefact of which stores reported.
- Egg prices swing within a band of roughly RM12.4–14.3 rather than trending up, and big rises tend to be followed by similar drops.
- Eggs and chicken both rose in June 2026. I did not investigate why.
- Every other monthly change with at least 30 matched stores was below 3.6%.
- **East Malaysia and cooking oil are stable.** East Malaysian egg and chicken changes stayed below 2.8% and 1.1% respectively (with 30+ stores), and cooking oil never moved more than 0.52% in a month (10+ matched stores).
- One case needs a caveat: eggs in East Malaysia rose 8.14% in Aug 2025 (RM13.56 → RM14.67), but only 24 stores were matched, below my 30-store minimum, so I treat it as inconclusive.

Over the whole year, the average chicken price in Peninsular Malaysia went from RM8.22 (Jul 2025) to RM9.32 (Jun 2026), while East Malaysia went from RM11.64 to RM11.30. The gap narrowed from RM3.42 to RM1.98, though the end point is sensitive because June 2026 had just jumped.

## Limitations

- **PriceCatcher is a price-surveillance dataset.** DOSM states it should complement, not replace, the CPI for inflation analysis. It is not sales-weighted and store coverage differs by state.
- **Only three items** in one pack size each, so the results do not describe the whole grocery basket.
- **Small samples** for some states (W.P. Labuan, Perlis) and for East Malaysian convenience stores.
- **Cleaning thresholds are judgement calls** based on price distributions. They remove 0.03% of rows and do not change the state ranking.
- **Causes are not tested.** The analysis describes where and when prices differ, not why.
- **Same-store comparison uses store-level monthly averages.** Items not sold in a store in both months drop out.

## How to reproduce

Requires Python 3 and a local MySQL server (I used XAMPP).

```
pip install -r requirements.txt
```

1. Create an empty MySQL database named `pricecatcher`.
2. Run `python scripts/download_data.py` from the project root. It downloads the 12 monthly files and writes three CSV files.
3. Edit the connection settings at the top of `scripts/load_mysql.py` if needed, then run `python scripts/load_mysql.py`.
4. Run the sections of `queries.sql` in order (for example in phpMyAdmin).

## Repository structure

```
├── README.md
├── queries.sql           # all SQL, in the order it was run
├── requirements.txt
└── scripts/
    ├── download_data.py  # download, filter, save CSV
    └── load_mysql.py     # create tables and load into MySQL
```

## Data source and licence

Source: KPDN PriceCatcher via data.gov.my / OpenDOSM, released under the [Creative Commons Attribution 4.0 International licence](https://creativecommons.org/licenses/by/4.0/).