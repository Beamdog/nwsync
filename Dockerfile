FROM nimlang/nim:alpine

COPY . /nwsync

RUN apk --no-cache add pcre \
  && cd nwsync \
  && nimble install -y \
  && cd -

ENV PATH="/nwsync/bin:${PATH}"
