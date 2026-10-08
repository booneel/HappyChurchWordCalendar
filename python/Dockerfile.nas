FROM python:3.11-slim

WORKDIR /app
COPY nas_requirements.txt .
RUN pip install --no-cache-dir -r nas_requirements.txt
COPY nas_api.py .

ENV WORDCALENDAR_NAS_ROOT=/data
ENV WORDCALENDAR_NAS_HOST=0.0.0.0
ENV WORDCALENDAR_NAS_PORT=8787
EXPOSE 8787

CMD ["python", "nas_api.py"]
