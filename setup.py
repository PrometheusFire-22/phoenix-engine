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
)
