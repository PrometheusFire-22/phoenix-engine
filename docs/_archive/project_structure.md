project-chronos/
├── .devcontainer/              # VS Code Dev Container config
│   ├── devcontainer.json
│   └── Dockerfile
├── .github/                    # GitHub workflows (future)
│   └── workflows/
├── database/                   # All database artifacts
│   ├── migrations/             # Future: Alembic migrations
│   ├── seeds/                  # Reference data
│   ├── schema.sql              # Core schema
│   ├── views.sql               # Analytical views
│   └── analytics_views.sql     # Advanced analytics
├── docs/                       # Documentation
│   ├── api_guides/
│   │   └── fred.md
│   ├── architecture.md
│   ├── DATA_QUALITY_CHECKLIST.md
│   ├── FX_RATES_METHODOLOGY.md
│   ├── SCHEMA_REFERENCE.md
│   └── USER_GUIDE.md
├── logs/                       # Application logs (gitignored)
├── scripts/                    # Operational scripts (ROOT LEVEL)
│   ├── daily_update.sh
│   └── setup_dev_env.sh
├── src/                        # Python source code
│   ├── chronos/
│   │   ├── __init__.py
│   │   ├── config/
│   │   │   ├── __init__.py
│   │   │   └── settings.py
│   │   ├── database/
│   │   │   ├── __init__.py
│   │   │   └── connection.py
│   │   ├── ingestion/
│   │   │   ├── __init__.py
│   │   │   ├── base.py
│   │   │   ├── fred.py
│   │   │   └── valet.py
│   │   └── utils/
│   │       ├── __init__.py
│   │       ├── exceptions.py
│   │       └── logging.py
│   └── scripts/                # CLI entry points (in src for packaging)
│       ├── __init__.py
│       ├── ingest_fred.py
│       └── ingest_valet.py
├── tests/                      # Test suite
│   ├── conftest.py
│   ├── integration/
│   │   └── __init__.py
│   └── unit/
│       ├── __init__.py
│       └── test_connection.py
├── .env                        # Environment variables (gitignored)
├── .env.example                # Template
├── .gitignore                  # Git ignore rules
├── docker-compose.yml          # Docker services
├── Makefile                    # Build automation
├── pyproject.toml              # Modern Python config
├── README.md                   # Project overview
├── requirements.txt            # Python dependencies
└── setup.py                    # Package setup
