FROM python:3.12-slim

RUN pip install \
    dagster \
    dagster-postgres \
    dagster-docker

# Add code location code
WORKDIR /opt/dagster/app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Run dagster code server on port 4000
EXPOSE 4000

# CMD allows this to be overridden from run launchers or executors
CMD ["dagster", "code-server", "start", "-h", "0.0.0.0", "-p", "4000", "-f", "defs.py"] 