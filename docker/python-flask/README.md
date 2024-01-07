# Setup

```sh
docker build --network host . -t flask-docker:latest
docker run --rm -it -p 8080:8080 --name test flask-docker:latest

curl localhost:8080
<h1>Hello from Flask & Docker</h2>
```
