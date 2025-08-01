# Use the official PHP-FPM image
FROM php:8.2-fpm

# Create app directory
WORKDIR /var/www/html

# Copy the PHP script into the container
COPY index.php .

# Ensure permissions are correct (optional)
RUN chown -R www-data:www-data /var/www/html

# Expose the default PHP-FPM port
EXPOSE 9000

# Start PHP-FPM
CMD ["php-fpm"]
