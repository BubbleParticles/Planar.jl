FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements/pyproject.toml
COPY pyproject.toml .

# Install Python dependencies
RUN pip install --no-cache-dir -e ".[server]"

# Copy source code
COPY src/ /app/src/
COPY config/ /app/config/

# Expose ports
EXPOSE 8000

# Run the gateway
CMD ["python", "-m", "ccxt_gateway.main"]
