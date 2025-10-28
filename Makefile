.PHONY: help setup start stop test lint format clean

help:
	@echo "Project Chronos - Available Commands"
	@echo "====================================="
	@echo "setup    : Install dependencies"
	@echo "start    : Start Docker services"
	@echo "stop     : Stop Docker services"
	@echo "test     : Run test suite"
	@echo "lint     : Run code linting"
	@echo "format   : Format code with Black"
	@echo "clean    : Remove generated files"

setup:
	python -m venv venv
	. venv/bin/activate && pip install -r requirements.txt

start:
	docker-compose up -d
	@echo "✅ Database started on localhost:5432"

stop:
	docker-compose down

test:
	pytest tests/ -v --cov=src/chronos

lint:
	ruff check src/ tests/

format:
	black src/ tests/

clean:
	find . -type d -name __pycache__ -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache .coverage htmlcov