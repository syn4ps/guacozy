ARG BUILDFRONTENDFROM=node:12.2.0-alpine
ARG SERVERFROM=python:3.7-alpine

####################
# BUILDER FRONTEND #
####################

FROM ${BUILDFRONTENDFROM} as builder-frontend
ADD frontend/package.json /frontend/
ADD frontend/package-lock.json /frontend/
WORKDIR /frontend
RUN npm install
ADD frontend /frontend
RUN npm run build

##################
# BUILDER WHEELS #
##################

FROM ${SERVERFROM} as builder-wheels

# set work directory
WORKDIR /usr/src/app

# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install psycopg2 dependencies
RUN apk update && apk add \
    build-base \
    ca-certificates \
    musl-dev \
    postgresql-dev \
    python3-dev \
    libffi-dev \
    openldap-dev

COPY guacozy_server/requirements*.txt ./
RUN pip wheel --no-cache-dir --wheel-dir /usr/src/app/wheels -r requirements-ldap.txt

#########
# FINAL #
#########

FROM ${SERVERFROM}

COPY --from=builder-wheels /usr/src/app/wheels /wheels

# install dependencies
RUN apk update && apk add --no-cache \
      bash \
      libpq \
      ca-certificates \
      nginx \
	  supervisor

# Inject built wheels and install them
COPY --from=builder-wheels /usr/src/app/wheels /wheels
RUN pip install --no-cache /wheels/*

# Inject django app
COPY guacozy_server  /app

# Inject built frontend
COPY --from=builder-frontend /frontend/build /frontend

# Inject docker specific configuration
COPY docker /tmp/docker

# Distribute configuration files and prepare dirs for pidfiles
RUN mkdir -p /run/nginx && \
    mkdir -p /run/daphne && \
    cd /tmp/docker && \
    mv entrypoint.sh /entrypoint.sh && \
    chmod +x /entrypoint.sh && \
    mv nginx-app.conf /etc/nginx/conf.d/ && \
    mkdir -p /etc/supervisor.d/ && \
    # create /app/.env if doesn't exists for less noise from django-environ
    touch /app/.env

ENTRYPOINT ["/entrypoint.sh"]

# Change to app dir so entrypoint.sh can run ./manage.py and other things localy to django
WORKDIR /app

CMD ["supervisord", "-n"]
EXPOSE 8080