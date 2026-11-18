FROM python:3.12-slim-bookworm@sha256:935c3c5b12357a7e10caa9c1e6ca5692344d97cf229832ef584be2cec9fc03df
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY deploy/couple/requirements.lock /tmp/requirements.lock
RUN python -m pip install --no-cache-dir --only-binary=:all: --require-hashes -r /tmp/requirements.lock \
    && groupadd -g 10001 couple && useradd -u 10001 -g couple --no-create-home couple \
    && install -d -m 0700 -o couple -g couple /data
COPY prompts/dp-relationship.zh-CN.md /app/prompts/dp-relationship.zh-CN.md
COPY services/couple/*.py /app/services/couple/
COPY deploy/couple/data_tool.py /app/data_tool.py
USER 10001:10001
CMD ["python","-m","uvicorn","services.couple.api:app","--host","0.0.0.0","--port","8787","--workers","1","--no-access-log"]
