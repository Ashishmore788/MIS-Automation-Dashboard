import pandas as pd
from sqlalchemy import create_engine

engine = create_engine('postgresql://postgres:Ashish%402710@localhost:5432/mis_dashboard')

df = pd.read_csv('C:/Users/HP/Downloads/VBA/Master_Data.csv')

df.to_sql('stg_tickets', engine, if_exists='replace', index=False)

print(f"Loaded {len(df)} rows into stg_tickets")