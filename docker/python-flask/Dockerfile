ARG PYTHON_VERSION=3.9.2
FROM python:$PYTHON_VERSION
ARG ENVIRONMENT=dev
ENV ENVIRONMENT $ENVIRONMENT

WORKDIR app
COPY requirements.txt requirements.txt
RUN pip3 install -r requirements.txt
COPY . .
CMD [ "python3", "app.py"]
