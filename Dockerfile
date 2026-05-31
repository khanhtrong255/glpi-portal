# ============================================================
# GLPI Dockerfile
# Base: php:8.3-apache (khuyến nghị cho GLPI 11.x)
# ============================================================
FROM php:8.3-apache

ARG GLPI_VERSION
ENV GLPI_VERSION=${GLPI_VERSION}

# --- Cài dependencies hệ thống ---
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

# --- Cài PHP extensions ---
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

# --- Cài PECL extensions ---
RUN pecl install apcu \
    && docker-php-ext-enable apcu

# --- PHP config tối ưu cho GLPI ---
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

# --- OPcache config ---
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.revalidate_freq=60'; \
} > /usr/local/etc/php/conf.d/opcache.ini

# --- Apache config ---
RUN a2enmod rewrite headers expires

# --- Tải & cài GLPI ---
WORKDIR /var/www
RUN wget -q "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
    -O /tmp/glpi.tgz \
    && tar -xzf /tmp/glpi.tgz -C /var/www/ \
    && rm /tmp/glpi.tgz

# --- Cấu hình Apache VirtualHost ---
COPY apache-glpi.conf /etc/apache2/sites-available/glpi.conf
RUN a2dissite 000-default.conf \
    && a2ensite glpi.conf

# --- Chuẩn bị thư mục dữ liệu ngoài webroot (bảo mật) ---
# Cấu trúc: webroot chỉ chứa code, dữ liệu lưu ở /var/glpi-data
RUN mkdir -p /var/glpi-data/files /var/glpi-data/config \
    && chown -R www-data:www-data /var/www/glpi /var/glpi-data

# --- Cron job cho GLPI task scheduler ---
COPY glpi-cron /etc/cron.d/glpi
RUN chmod 0644 /etc/cron.d/glpi && crontab /etc/cron.d/glpi

# --- Entrypoint ---
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]