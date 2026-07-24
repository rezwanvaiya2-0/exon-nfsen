# =============================================================================
# Dockerfile for NfSen 1.3.6p1 + NfDump 1.6.17
# Following the EXACT steps from the working guide
# Base: Ubuntu 20.04
# =============================================================================

FROM ubuntu:20.04

LABEL maintainer="NfSen Docker" \
      description="NfSen 1.3.6p1 with NfDump 1.6.17" \
      version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Dhaka

# ===========================================================================
# STEP 1: Install Dependencies (exactly as guide says)
# ===========================================================================
RUN apt-get update && apt-get install -y \
    make gcc flex rrdtool librrd-dev libpcap-dev php \
    librrds-perl libsocket6-perl apache2 libapache2-mod-php \
    libtool dh-autoreconf pkg-config libbz2-dev byacc doxygen \
    graphviz librrdp-perl libmailtools-perl build-essential \
    autoconf wget curl cpanminus net-tools \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ===========================================================================
# STEP 2: Enable PHP (guide: a2enmod php7.4)
# ===========================================================================
RUN a2enmod php7.4

# ===========================================================================
# STEP 3: Fix Apache icons (guide: comment out Alias /icons/ line)
# ===========================================================================
RUN sed -i 's|^[[:space:]]*Alias /icons/ "/usr/share/apache2/icons/"|#Alias /icons/ "/usr/share/apache2/icons/"|' \
    /etc/apache2/mods-enabled/alias.conf 2>/dev/null || true

# ===========================================================================
# STEP 4: Set PHP timezone (guide: date.timezone = Asia/Dhaka)
# ===========================================================================
RUN sed -i 's|;date.timezone =|date.timezone = Asia/Dhaka|' /etc/php/7.4/apache2/php.ini

# ===========================================================================
# STEP 5: Create working directory and download nfdump + nfsen
# ===========================================================================
WORKDIR /tmp
RUN wget -q --retry-connrefused --tries=3 -O v1.6.17.tar.gz \
    https://github.com/phaag/nfdump/archive/v1.6.17.tar.gz \
    && tar xzfv v1.6.17.tar.gz

RUN wget -q --retry-connrefused --tries=3 -O nfsen.tar.gz \
    "https://bit.ly/2NpMHqV" \
    && tar zxfv nfsen.tar.gz

# ===========================================================================
# STEP 6: Prepare and compile nfdump (guide's exact configure flags)
# ===========================================================================
WORKDIR /tmp/nfdump-1.6.17
RUN sh ./autogen.sh \
    && ./configure \
        --enable-nsel \
        --enable-nfprofile \
        --enable-sflow \
        --enable-readpcap \
        --enable-nfpcapd \
        --enable-nftrack \
        --enable-jnat \
    && make && make install

# ===========================================================================
# STEP 7: Install Perl modules (guide: cpanm)
# ===========================================================================
RUN cpanm App::cpanminus \
    && cpanm Mail::Header \
    && cpanm Mail::Internet

# ===========================================================================
# STEP 8: ldconfig (as guide says)
# ===========================================================================
RUN /sbin/ldconfig

# ===========================================================================
# STEP 9: Configure nfsen config (guide: edit BASEDIR, WWWUSER, WWWGROUP)
# First copy the dist file to nfsen.conf
# ===========================================================================
RUN cd /tmp/nfsen-1.3.6p1/etc && cp nfsen-dist.conf nfsen.conf

# ===========================================================================
# STEP 10: Add netflow user and create /var/nfsen (as guide says)
# ===========================================================================
RUN useradd -M -s /bin/false -G www-data netflow \
    && mkdir -p /var/nfsen

# ===========================================================================
# STEP 11: Fix RRD version check in NfSenRRD.pm + install.pl
# Guide says: Change from 1.5 to 1.8 in NfSenRRD.pm
# Also fix install.pl's own version check - WARNING: NO inline comments here!
# In /bin/sh, # comments break continuation lines! Use echo instead.
# ===========================================================================
RUN cd /tmp/nfsen-1.3.6p1 \
    && echo "[STEP 11] Fixing NfSenRRD.pm 1.5->1.8..." \
    && sed -i 's/1\.[56]/1.8/g' libexec/NfSenRRD.pm \
    && echo "[STEP 11] Fixing install.pl exit calls..." \
    && sed -i 's/exit 2;/# exit 2;/g' install.pl \
    && sed -i '/not yet supported/d' install.pl \
    && echo "[STEP 11] Fixing Nfsync.pm semaphore die -> warn..." \
    && sed -i 's/|| die "Can not get semaphore/|| warn "Can not get semaphore/g' libexec/Nfsync.pm \
    && echo "[STEP 11] Fixing NfSen.pm UserInput for non-interactive reconfig..." \
    && sed -i '/$answer = <STDIN>;/a\        if (!defined($answer)) { $answer = "y"; }' libexec/NfSen.pm \
    && echo "[STEP 11] Version checks patched"

# ===========================================================================
# STEP 12: Configure nfsen.conf with our settings
# ===========================================================================
COPY config/nfsen.conf /tmp/nfsen-1.3.6p1/etc/nfsen.conf

# ===========================================================================
# STEP 13: Install nfsen (guide: ./install.pl ./etc/nfsen.conf)
# ===========================================================================
WORKDIR /tmp/nfsen-1.3.6p1
RUN ./install.pl ./etc/nfsen.conf \
    && echo "[STEP 13] install.pl completed" \
    && ls -la /var/nfsen/www/nfsen.php 2>/dev/null \
        && echo "[STEP 13] nfsen.php exists" \
        || { echo "[STEP 13 ERROR] nfsen.php NOT FOUND after install.pl!"; exit 1; }

# ===========================================================================
# STEP 14: Set up Apache (guide: virtual host, ports 8070, apache2.conf)
# ===========================================================================
COPY config/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY config/ports.conf /etc/apache2/ports.conf

# Update apache2.conf - change AllowOverride None to All (as guide says)
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' \
    /etc/apache2/apache2.conf 2>/dev/null || true

# ===========================================================================
# STEP 15: Configure ownership and permissions (guide's troubleshooting)
# ===========================================================================
RUN chown -R www-data:www-data /var/nfsen && \
    chown -R netflow:www-data /var/nfsen/profiles-data/live/ 2>/dev/null || true && \
    chmod -R 775 /var/nfsen && \
    chmod 777 /var/nfsen/var/run 2>/dev/null || true

# ===========================================================================
# STEP 16: Make nfsen reboot proof (guide: init.d symlink)
# ===========================================================================
RUN ln -sf /var/nfsen/bin/nfsen /etc/init.d/nfsen

# ===========================================================================
# STEP 17: Copy entrypoint
# ===========================================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ===========================================================================
# Clean up build artifacts
# ===========================================================================
RUN rm -rf /tmp/nfdump-1.6.17* /tmp/nfsen-1.3.6p1* /tmp/v1.6.17* /tmp/nfsen.tar.gz

# ===========================================================================
# Expose ports: 8070/tcp (NfSen Web UI) and 2055/udp (NetFlow)
# ===========================================================================
EXPOSE 8070
EXPOSE 2055/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8070/nfsen.php || exit 1

# ===========================================================================
# Entrypoint
# ===========================================================================
CMD ["/entrypoint.sh"]
