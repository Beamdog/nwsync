FROM nimlang/nim:alpine

COPY . /nwsync

RUN apk --no-cache add curl unzip pcre \
  && cd nwsync \
  && nimble install -y \
  && cd -

ENV PATH="/nwsync/bin:${PATH}"
