ARG BUILD_FROM
FROM $BUILD_FROM

# Install required packages
RUN apk add --no-cache \
    bash \
    openssh-client \
    rsync \
    dcron \
    tzdata \
    python3 \
    py3-pip \
    sshpass \
    expect \
    jq

# Install Flask for web UI (use system package to avoid PEP 668 error)
RUN apk add --no-cache py3-flask

# Create app directory
WORKDIR /app

# Copy scripts
COPY run.sh /
COPY web_ui.py /app/
COPY templates/ /app/templates/

RUN chmod a+x /run.sh

CMD [ "/run.sh" ]