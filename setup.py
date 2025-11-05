from setuptools import setup, find_packages

setup(
    name="project-chronos",
    version="0.2.0",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    python_requires=">=3.11",
    install_requires=[
        "sqlalchemy>=2.0.23",
        "psycopg2-binary>=2.9.9",
        "requests>=2.31.0",
        "pandas>=2.1.4",
        "python-dotenv>=1.0.0",
        "pydantic>=2.5.3",
        "pydantic-settings>=2.1.0",
        "structlog>=23.3.0",
        "click>=8.1.7",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.3",
            "pytest-cov>=4.1.0",
            "black>=23.12.1",
            "ruff>=0.1.9",
            "bandit>=1.7.5",
            "safety>=2.3.5",
            "pip-audit>=2.6.1",
        ],
    },
)
