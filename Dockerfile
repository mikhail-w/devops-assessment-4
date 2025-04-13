FROM python:3.9-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn

# Copy the rest of the application
COPY . .

# Set environment variables
ENV FLASK_APP=app.py
ENV FLASK_RUN_HOST=0.0.0.0
ENV FLASK_RUN_PORT=8080

# Expose port 8080
EXPOSE 8080

# Run with Gunicorn instead of Flask development server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]