#!/usr/bin/env python3
"""
============================================================================
Phoenix Engine V2.0 - Backfill Script (Ingestion Layer)
============================================================================
Purpose: "DUMB" data loader - Extract from yfinance, Load to PostgreSQL
Principle: NO transformations - store raw TTM data exactly as received
============================================================================
"""

import os
import sys
import time
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import pandas as pd
import yfinance as yf
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
from tqdm import tqdm
from colorama import Fore, Style, init
from dotenv import load_dotenv

# Initialize colorama for cross-platform colored output
init(autoreset=True)

# Load environment variables
load_dotenv()

# Configure yfinance session with better headers
import requests
yf_session = requests.Session()
yf_session.headers.update({
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
})

# ============================================================================
# CONFIGURATION
# ============================================================================

DATABASE_URL = os.getenv('DATABASE_URL')
MASTER_CSV_PATH = 'data/master_company_list.csv'
FX_CSV_PATH = 'data/fx_rates_list.csv'

# yfinance settings
MAX_HISTORY_PERIOD = "max"  # Get all available historical data
PRICE_INTERVAL = "1d"       # Daily price data

# ============================================================================
# DATABASE CONNECTION
# ============================================================================

def get_db_engine():
    """Create SQLAlchemy engine with connection pooling."""
    if not DATABASE_URL:
        raise ValueError("DATABASE_URL not found in environment variables")
    
    return create_engine(
        DATABASE_URL,
        pool_pre_ping=True,  # Verify connections before using
        pool_size=5,
        max_overflow=10
    )

# ============================================================================
# LOGGING UTILITIES
# ============================================================================

class IngestionLogger:
    """Handles logging to both console and database."""
    
    def __init__(self, engine):
        self.engine = engine
        self.run_id = None
        self.start_time = datetime.now()
        self.stats = {
            'tickers_processed': 0,
            'tickers_failed': 0,
            'price_records': 0,
            'financial_records': 0,
            'errors': []
        }
    
    def start_run(self):
        """Log the start of a backfill run."""
        with self.engine.connect() as conn:
            result = conn.execute(text("""
                INSERT INTO ingestion_log (script_name, status, notes)
                VALUES ('backfill.py', 'STARTED', 'Backfill started')
                RETURNING log_id
            """))
            conn.commit()
            self.run_id = result.fetchone()[0]
        
        print(f"\n{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}Phoenix Engine V2.0 - Backfill Started")
        print(f"{Fore.CYAN}Run ID: {self.run_id}")
        print(f"{Fore.CYAN}{'='*70}\n")
    
    def log_ticker_success(self, ticker: str, price_count: int, financial_count: int):
        """Log successful ticker ingestion."""
        self.stats['tickers_processed'] += 1
        self.stats['price_records'] += price_count
        self.stats['financial_records'] += financial_count
        print(f"{Fore.GREEN}✓ {ticker}: {price_count} prices, {financial_count} financials")
    
    def log_ticker_failure(self, ticker: str, error: str):
        """Log failed ticker ingestion."""
        self.stats['tickers_failed'] += 1
        self.stats['errors'].append(f"{ticker}: {error}")
        print(f"{Fore.RED}✗ {ticker}: {error}")
        
        # Log to data quality table
        with self.engine.connect() as conn:
            conn.execute(text("""
                INSERT INTO data_quality_issues 
                (ticker, issue_type, severity, description)
                VALUES (:ticker, 'INGESTION_FAILURE', 'ERROR', :error)
            """), {'ticker': ticker, 'error': error})
            conn.commit()
    
    def end_run(self, status: str = 'SUCCESS'):
        """Log the end of a backfill run."""
        duration = (datetime.now() - self.start_time).total_seconds()
        
        with self.engine.connect() as conn:
            conn.execute(text("""
                UPDATE ingestion_log
                SET status = :status,
                    tickers_processed = :processed,
                    tickers_failed = :failed,
                    records_inserted = :records,
                    duration_seconds = :duration,
                    error_message = :errors
                WHERE log_id = :run_id
            """), {
                'status': status,
                'processed': self.stats['tickers_processed'],
                'failed': self.stats['tickers_failed'],
                'records': self.stats['price_records'] + self.stats['financial_records'],
                'duration': int(duration),
                'errors': '\n'.join(self.stats['errors'][:10]) if self.stats['errors'] else None,
                'run_id': self.run_id
            })
            conn.commit()
        
        print(f"\n{Fore.CYAN}{'='*70}")
        print(f"{Fore.CYAN}Backfill Complete - Run ID: {self.run_id}")
        print(f"{Fore.GREEN}✓ Success: {self.stats['tickers_processed']} tickers")
        print(f"{Fore.RED}✗ Failed: {self.stats['tickers_failed']} tickers")
        print(f"{Fore.YELLOW}📊 Price records: {self.stats['price_records']:,}")
        print(f"{Fore.YELLOW}📊 Financial records: {self.stats['financial_records']:,}")
        print(f"{Fore.CYAN}⏱️  Duration: {int(duration)}s")
        print(f"{Fore.CYAN}{'='*70}\n")

# ============================================================================
# DATA LOADING FUNCTIONS
# ============================================================================

def load_master_csv() -> pd.DataFrame:
    """Load and validate master company list."""
    print(f"{Fore.YELLOW}Loading master company list from {MASTER_CSV_PATH}...")
    
    if not os.path.exists(MASTER_CSV_PATH):
        raise FileNotFoundError(f"Master CSV not found: {MASTER_CSV_PATH}")
    
    df = pd.read_csv(MASTER_CSV_PATH)
    
    # Validate required columns
    required_cols = ['ticker', 'company_name', 'sector', 'sub_sector', 'source_name']
    missing_cols = set(required_cols) - set(df.columns)
    if missing_cols:
        raise ValueError(f"Missing required columns: {missing_cols}")
    
    # Clean data
    df['ticker'] = df['ticker'].str.strip().str.upper()
    df['company_name'] = df['company_name'].str.strip()
    
    print(f"{Fore.GREEN}✓ Loaded {len(df)} rows, {df['ticker'].nunique()} unique tickers\n")
    
    return df

def populate_reference_tables(engine, df: pd.DataFrame):
    """Populate sources, companies, and company_sources tables."""
    print(f"{Fore.YELLOW}Populating reference tables...")
    
    with engine.connect() as conn:
        # 1. Insert unique sources
        sources = df[['source_name']].drop_duplicates()
        for _, row in sources.iterrows():
            conn.execute(text("""
                INSERT INTO sources (source_name, source_type)
                VALUES (:name, 'ETF')
                ON CONFLICT (source_name) DO NOTHING
            """), {'name': row['source_name']})
        
        # 2. Insert unique companies with metadata
        companies = df.groupby('ticker').first().reset_index()
        for _, row in companies.iterrows():
            # Parse exchange and country from ticker
            exchange, country = parse_ticker_metadata(row['ticker'])
            
            conn.execute(text("""
                INSERT INTO companies 
                (ticker, company_name, sector, sub_sector, exchange, country_code, is_active)
                VALUES (:ticker, :name, :sector, :sub_sector, :exchange, :country, TRUE)
                ON CONFLICT (ticker) DO UPDATE
                SET company_name = EXCLUDED.company_name,
                    sector = EXCLUDED.sector,
                    sub_sector = EXCLUDED.sub_sector,
                    updated_at = CURRENT_TIMESTAMP
            """), {
                'ticker': row['ticker'],
                'name': row['company_name'],
                'sector': row['sector'],
                'sub_sector': row['sub_sector'],
                'exchange': exchange,
                'country': country
            })
        
        # 3. Insert company-source relationships
        for _, row in df.iterrows():
            conn.execute(text("""
                INSERT INTO company_sources (company_id, source_id)
                SELECT c.company_id, s.source_id
                FROM companies c, sources s
                WHERE c.ticker = :ticker AND s.source_name = :source
                ON CONFLICT (company_id, source_id) DO NOTHING
            """), {'ticker': row['ticker'], 'source': row['source_name']})
        
        conn.commit()
    
    print(f"{Fore.GREEN}✓ Reference tables populated\n")

def parse_ticker_metadata(ticker: str) -> Tuple[Optional[str], Optional[str]]:
    """Extract exchange and country code from ticker symbol."""
    # International ticker patterns
    exchange_map = {
        '.KS': ('KS', 'KR'),   # Korea
        '.TW': ('TW', 'TW'),   # Taiwan
        '.HK': ('HK', 'HK'),   # Hong Kong
        '.AS': ('AS', 'NL'),   # Amsterdam (Netherlands)
        '.AX': ('AX', 'AU'),   # Australia
        '.DE': ('DE', 'DE'),   # Germany (XETRA)
        '.TO': ('TO', 'CA'),   # Toronto (Canada)
        '.HE': ('HE', 'FI'),   # Helsinki (Finland)
        '.SW': ('SW', 'CH'),   # Swiss (Switzerland)
        '.MI': ('MI', 'IT'),   # Milan (Italy)
        '.L': ('L', 'GB'),     # London (UK)
        '.PA': ('PA', 'FR'),   # Paris (France)
    }
    
    for suffix, (exchange, country) in exchange_map.items():
        if suffix in ticker:
            return exchange, country
    
    # Default to US
    return 'US', 'US'

# ============================================================================
# YFINANCE DATA FETCHING
# ============================================================================

def fetch_price_data(ticker: str, retry_count: int = 3) -> Optional[pd.DataFrame]:
    """Fetch historical daily prices from yfinance with retry logic."""
    for attempt in range(retry_count):
        try:
            # Add delay between retries
            if attempt > 0:
                wait_time = 2 ** attempt  # Exponential backoff: 2s, 4s
                time.sleep(wait_time)
            
            stock = yf.Ticker(ticker, session=yf_session)
            hist = stock.history(period=MAX_HISTORY_PERIOD, interval=PRICE_INTERVAL)
            
            if hist.empty:
                return None
            
            # Prepare dataframe for database
            hist = hist.reset_index()
            hist['ticker'] = ticker
            hist.columns = [
                'price_date', 'open_price', 'high_price', 'low_price', 
                'close_price', 'volume', 'dividends', 'stock_splits', 'ticker'
            ]
            
            # Add adj_close (same as close for now, yfinance handles adjustments)
            hist['adj_close_price'] = hist['close_price']
            
            # Select only needed columns
            hist = hist[['ticker', 'price_date', 'open_price', 'high_price', 
                         'low_price', 'close_price', 'adj_close_price', 'volume']]
            
            return hist
        
        except Exception as e:
            if attempt == retry_count - 1:  # Last attempt
                raise Exception(f"Price fetch error after {retry_count} attempts: {str(e)}")
            continue  # Try again
    
    return None

def fetch_financial_data(ticker: str, retry_count: int = 3) -> Optional[pd.DataFrame]:
    """Fetch quarterly financial data (TTM values) from yfinance with retry logic."""
    for attempt in range(retry_count):
        try:
            # Add delay between retries
            if attempt > 0:
                wait_time = 2 ** attempt
                time.sleep(wait_time)
            
            stock = yf.Ticker(ticker, session=yf_session)
            
            # Get quarterly financials (yfinance provides TTM automatically)
            income_stmt = stock.quarterly_income_stmt
            balance_sheet = stock.quarterly_balance_sheet
            cash_flow = stock.quarterly_cashflow
            
            if income_stmt.empty:
                return None
            
            # yfinance returns data with dates as columns - transpose
            financials = []
            
            for date in income_stmt.columns:
                try:
                    record = {
                        'ticker': ticker,
                        'fiscal_date': date.date(),
                        'report_period': f"{date.year}Q{(date.month-1)//3 + 1}",
                        
                        # Income Statement (TTM values from yfinance)
                        'total_revenue_ttm': safe_get(income_stmt, 'Total Revenue', date),
                        'cost_of_revenue_ttm': safe_get(income_stmt, 'Cost Of Revenue', date),
                        'gross_profit_ttm': safe_get(income_stmt, 'Gross Profit', date),
                        'operating_income_ttm': safe_get(income_stmt, 'Operating Income', date),
                        'net_income_ttm': safe_get(income_stmt, 'Net Income', date),
                        'ebitda_ttm': safe_get(income_stmt, 'EBITDA', date),
                        
                        # Balance Sheet (Point-in-time)
                        'total_assets': safe_get(balance_sheet, 'Total Assets', date),
                        'total_liabilities': safe_get(balance_sheet, 'Total Liabilities Net Minority Interest', date),
                        'stockholders_equity': safe_get(balance_sheet, 'Stockholders Equity', date),
                        'cash_and_equivalents': safe_get(balance_sheet, 'Cash And Cash Equivalents', date),
                        'short_term_debt': safe_get(balance_sheet, 'Current Debt', date),
                        'long_term_debt': safe_get(balance_sheet, 'Long Term Debt', date),
                        
                        # Cash Flow (TTM values from yfinance)
                        'operating_cash_flow_ttm': safe_get(cash_flow, 'Operating Cash Flow', date),
                        'capital_expenditure_ttm': safe_get(cash_flow, 'Capital Expenditure', date),
                        'free_cash_flow_ttm': safe_get(cash_flow, 'Free Cash Flow', date),
                        
                        # Share data
                        'shares_outstanding': safe_get(balance_sheet, 'Ordinary Shares Number', date),
                    }
                    
                    financials.append(record)
                
                except Exception as e:
                    continue  # Skip malformed quarters
            
            if not financials:
                return None
            
            return pd.DataFrame(financials)
        
        except Exception as e:
            if attempt == retry_count - 1:
                raise Exception(f"Financial fetch error after {retry_count} attempts: {str(e)}")
            continue
    
    return None

def safe_get(df: pd.DataFrame, row_name: str, col_date) -> Optional[float]:
    """Safely extract value from yfinance dataframe."""
    try:
        if row_name in df.index and col_date in df.columns:
            val = df.loc[row_name, col_date]
            if pd.notna(val):
                return float(val)
        return None
    except:
        return None

# ============================================================================
# DATABASE INSERTION
# ============================================================================

def insert_price_data(engine, df: pd.DataFrame) -> int:
    """Insert price data using ON CONFLICT to handle duplicates."""
    if df.empty:
        return 0
    
    with engine.connect() as conn:
        # Use executemany for bulk insert
        records = df.to_dict('records')
        conn.execute(text("""
            INSERT INTO raw_daily_prices 
            (ticker, price_date, open_price, high_price, low_price, 
             close_price, adj_close_price, volume)
            VALUES (:ticker, :price_date, :open_price, :high_price, :low_price,
                    :close_price, :adj_close_price, :volume)
            ON CONFLICT (ticker, price_date) DO UPDATE
            SET close_price = EXCLUDED.close_price,
                adj_close_price = EXCLUDED.adj_close_price,
                volume = EXCLUDED.volume,
                ingested_at = CURRENT_TIMESTAMP
        """), records)
        conn.commit()
    
    return len(df)

def insert_financial_data(engine, df: pd.DataFrame) -> int:
    """Insert financial data using ON CONFLICT to handle duplicates."""
    if df.empty:
        return 0
    
    with engine.connect() as conn:
        records = df.to_dict('records')
        conn.execute(text("""
            INSERT INTO raw_financials 
            (ticker, fiscal_date, report_period,
             total_revenue_ttm, cost_of_revenue_ttm, gross_profit_ttm,
             operating_income_ttm, net_income_ttm, ebitda_ttm,
             total_assets, total_liabilities, stockholders_equity,
             cash_and_equivalents, short_term_debt, long_term_debt,
             operating_cash_flow_ttm, capital_expenditure_ttm, free_cash_flow_ttm,
             shares_outstanding)
            VALUES (:ticker, :fiscal_date, :report_period,
                    :total_revenue_ttm, :cost_of_revenue_ttm, :gross_profit_ttm,
                    :operating_income_ttm, :net_income_ttm, :ebitda_ttm,
                    :total_assets, :total_liabilities, :stockholders_equity,
                    :cash_and_equivalents, :short_term_debt, :long_term_debt,
                    :operating_cash_flow_ttm, :capital_expenditure_ttm, :free_cash_flow_ttm,
                    :shares_outstanding)
            ON CONFLICT (ticker, fiscal_date) DO UPDATE
            SET total_revenue_ttm = EXCLUDED.total_revenue_ttm,
                net_income_ttm = EXCLUDED.net_income_ttm,
                ingested_at = CURRENT_TIMESTAMP
        """), records)
        conn.commit()
    
    return len(df)

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================

def backfill_ticker(engine, logger: IngestionLogger, ticker: str):
    """Fetch and load data for a single ticker."""
    try:
        # Add small delay to avoid rate limiting
        time.sleep(0.5)
        
        # Fetch price data
        price_df = fetch_price_data(ticker)
        price_count = 0
        if price_df is not None:
            price_count = insert_price_data(engine, price_df)
        
        # Fetch financial data
        financial_df = fetch_financial_data(ticker)
        financial_count = 0
        if financial_df is not None:
            financial_count = insert_financial_data(engine, financial_df)
        
        # Log success
        logger.log_ticker_success(ticker, price_count, financial_count)
    
    except Exception as e:
        logger.log_ticker_failure(ticker, str(e))

def main():
    """Main backfill orchestration."""
    import argparse
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Phoenix Engine Backfill Script')
    parser.add_argument('--fx', action='store_true', 
                       help='Load FX rates instead of company data')
    parser.add_argument('--test', action='store_true',
                       help='Test mode: only process first 5 tickers')
    args = parser.parse_args()
    
    try:
        # Initialize
        engine = get_db_engine()
        logger = IngestionLogger(engine)
        logger.start_run()
        
        # Select appropriate CSV
        csv_path = FX_CSV_PATH if args.fx else MASTER_CSV_PATH
        
        # Load master CSV
        print(f"{Fore.YELLOW}Loading data from {csv_path}...")
        master_df = load_master_csv() if not args.fx else load_fx_csv()
        
        # Populate reference tables
        populate_reference_tables(engine, master_df)
        
        # Get unique tickers
        tickers = master_df['ticker'].unique()
        
        # Sort tickers: US first (more reliable), then others
        us_tickers = [t for t in tickers if not any(suffix in t for suffix in ['.KS', '.TW', '.HK', '.AS', '.AX', '.DE', '.TO', '.HE', '.SW', '.MI', '.L', '.PA'])]
        intl_tickers = [t for t in tickers if t not in us_tickers]
        tickers = us_tickers + intl_tickers
        
        # Test mode: limit to 5 tickers
        if args.test:
            tickers = tickers[:5]
            print(f"{Fore.YELLOW}⚠️  TEST MODE: Processing only {len(tickers)} tickers (US only)\n")
        
        print(f"{Fore.CYAN}Starting data ingestion for {len(tickers)} tickers...\n")
        
        # Process each ticker with progress bar
        for ticker in tqdm(tickers, desc="Ingesting", unit="ticker"):
            backfill_ticker(engine, logger, ticker)
        
        # Determine final status
        status = 'SUCCESS' if logger.stats['tickers_failed'] == 0 else 'PARTIAL'
        logger.end_run(status)
        
        return 0
    
    except Exception as e:
        print(f"\n{Fore.RED}FATAL ERROR: {str(e)}")
        if 'logger' in locals():
            logger.end_run('FAILED')
        return 1

def load_fx_csv() -> pd.DataFrame:
    """Load FX rates CSV."""
    if not os.path.exists(FX_CSV_PATH):
        raise FileNotFoundError(f"FX CSV not found: {FX_CSV_PATH}")
    
    df = pd.read_csv(FX_CSV_PATH)
    df['ticker'] = df['ticker'].str.strip()
    
    print(f"{Fore.GREEN}✓ Loaded {len(df)} FX rate tickers\n")
    return df

if __name__ == "__main__":
    sys.exit(main())