# ============================================================
# GLPI Dockerfile - Tối ưu build cache
# Stage 1: base-php  — cài extensions (cache lâu dài)
# Stage 2: glpi-app  — tải GLPI + config (rebuild khi đổi version)
# ============================================================

# ---- Stage 1: PHP base với đầy đủ extensions ----
FROM php:8.3-apache AS base-php

# Cài dependencies hệ thống
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libldap2-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libxslt1-dev \
    libonig-dev \
    libbz2-dev \
    cron \
    unzip \
    wget \
    bzip2 \
    && rm -rf /var/lib/apt/lists/*

# Cài PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j$(nproc) \
        gd \
        pdo \
        pdo_mysql \
        mysqli \
        zip \
        intl \
        ldap \
        curl \
        xml \
        xsl \
        opcache \
        mbstring \
        exif \
        fileinfo \
        bcmath \
        bz2

# Cài PECL extensions
RUN pecl install apcu \
    && docker-php-ext-enable apcu

# PHP config
RUN { \
    echo 'memory_limit = 256M'; \
    echo 'max_execution_time = 600'; \
    echo 'max_input_vars = 5000'; \
    echo 'upload_max_filesize = 20M'; \
    echo 'post_max_size = 20M'; \
    echo 'session.cookie_httponly = On'; \
    echo 'session.cookie_secure = Off'; \
    echo 'date.timezone = Asia/Ho_Chi_Minh'; \
} > /usr/local/etc/php/conf.d/glpi-php.ini

# OPcache config
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=60'; \
} > /usr/local/etc/php/conf.d/opcache.ini

# Apache modules
RUN a2enmod rewrite headers expires

# ---- Stage 2: GLPI app (rebuild nhanh khi đổi version) ----
FROM base-php AS glpi-app

ARG GLPI_VERSION
ENV GLPI_VERSION=${GLPI_VERSION}

# Tải GLPI — layer này mới rebuild khi GLPI_VERSION thay đổi
WORKDIR /var/www

# Copy file cai dat vao thu muc tmp
COPY glpi-${GLPI_VERSION}.tgz /tmp/glpi.tgz
RUN tar -xzf /tmp/glpi.tgz -C /var/www/ && rm /tmp/glpi.tgz

# Apache VirtualHost
COPY apache-glpi.conf /etc/apache2/sites-available/glpi.conf
RUN a2dissite 000-default.conf && a2ensite glpi.conf

# Thư mục dữ liệu ngoài webroot
RUN mkdir -p /var/glpi-data/files /var/glpi-data/config

# Cron job
COPY glpi-cron /etc/cron.d/glpi
RUN chmod 0644 /etc/cron.d/glpi

# Entrypoint
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]