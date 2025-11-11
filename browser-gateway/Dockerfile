FROM python:3.10
WORKDIR /app
RUN apt-get update && apt-get install -y xvfb chromium-driver chromium-browser
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY gateway.py .
EXPOSE 5900 8000
CMD ["python", "gateway.py"]
