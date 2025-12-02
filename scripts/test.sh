#!/bin/bash

echo "🧪 Running Brain Graph Tests..."

# Activate virtual environment if exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Check if test database exists
if ! PGPASSWORD=postgres psql -U postgres -lqt | cut -d \| -f 1 | grep -qw brain_graph_test; then
    echo "Creating test database..."
    PGPASSWORD=postgres psql -U postgres -c "CREATE DATABASE brain_graph_test;"
    PGPASSWORD=postgres psql -U postgres -d brain_graph_test -f migrations/001_brain_graph_complete_v3.sql
fi

# Run tests
pytest tests/ -v --cov=backend/app --cov-report=html --cov-report=term

echo ""
echo "📊 Coverage report: htmlcov/index.html"
