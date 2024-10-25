# syntax=docker/dockerfile:1
FROM archlinux/archlinux:base-devel
ARG DATE="2024-10-02"
ARG VERSION="v0.0.0"
LABEL org.opencontainers.image.authors="xander@platonic.io"
LABEL org.opencontainers.image.date="${DATE}"
LABEL org.opencontainers.image.source="https://github.com/platonic-io/symenv"
LABEL org.opencontainers.image.version="${VERSION}"
RUN pacman -Syyu --noconfirm \
    bash-completion \
    curl \
    git \
    jq \
    unzip \
    vim \
    wget \
    zip \
    zsh \
    && ln -sfv /usr/bin/vim /usr/bin/vi \
    && useradd -s /bin/bash -m -g users -d /home/symenv symenv
COPY docker/.zshrc /home/symenv/.zshrc
COPY docker/.bashrc /home/symenv/.bashrc
USER symenv
RUN curl -L https://raw.githubusercontent.com/symbiont-io/symenv/main/install.sh | bash
WORKDIR /home/symenv/
CMD ["/bin/bash"]