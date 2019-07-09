# Wordpress Proxy
HTTP Caching Proxy Layer docker image for Wordpress

# Description
Wordpress Proxy is a reverse proxy caching layer for Wordpress. It is based on the official Nginx Docker image.

Typically, a Worpress site is deployed on top of a Linux, Apache, Mysql and PHP (LAMP) stack. After a fresh install, with minimal plugins and a basic theme, page load times on a Wordpress times is quite low.

However, on a typical site with several plugins and a complex theme installed, page load times can be significant. This is because each time a page is accessed, Wordpress has to generate each page dynamically from its content and the Mysql database.

To improve page load times for our users, we can put the Wordpress site behind a proxy caching layer (wordpress-proxy).

When a user access a page for the first time through the proxy, it first fetches the content from the Wordpress site. This content is then cached in memory, and served to the user.

Subsequent page accesses through the proxy will simply load the content from the cache. This results in a much shorter page load times.

# How to use this image
The following are example deployments using `docker-compose`
## Independant deployment
```yaml
version: '3'

services:
  wordpress-proxy:
    image: ragibkl/wordpress-proxy
    ports:
      - 80:80
    environment:
      UPSTREAM_URL: http://wordpress.domain.example     # base url of the upstream wordpress site
      # UPSTREAM_URL: http://123.123.123.123            # base url of the upstream wordpress using ip address
      # UPSTREAM_URL: http://localhost:8080             # base url of the upstream wordpress running locally on a different port
```

## Deployed together with Wordpress
```yaml
version: '3'

services:
  mariadb:
    image: mariadb:10
    volumes:
      - mariadb-data:/var/lib/mysql
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_PASSWORD: password
      MYSQL_ROOT_PASSWORD: password
      MYSQL_USER: user

  wordpress:
    image: wordpress
    volumes:
      - wordpress-data:/var/www/html/wp-content
    environment:
      WORDPRESS_DB_HOST: mariadb
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_PASSWORD: password
      WORDPRESS_DB_USER: user

  wordpress-proxy:
    image: ragibkl/wordpress-proxy
    ports:
      - 80:80
    environment:
      UPSTREAM_URL: http://wordpress    # base url of the upstream wordpress site. should be the same name as the wordpress container

volumes:
  mariadb-data:
  wordpress-data:
```

# Development

## Getting Started
1. Ensure that `docker` and `docker-compose` are installed on your machine
2. Clone this repo and cd into the project directory
    ```
    git clone git@github.com:ragibkl/wordpress-proxy.git
    cd wordpress-proxy
    ```
3. Run the start script. This will generate a simple nginx config file. Next, it will spin up a Wordpress site, behind a worpress-proxy nginx service to run locally
    ```
    ./scripts/start.sh
    ```
4. Give it a few minutes. Try accessing `http://localhost/` from your browser. Once everything is loaded, go ahead and install the site as normal
5. During development, after making changes to the related files, run the start script again to see your changes
6. When done, run the stop script. This will also remove any data or volumes that were created during development
    ```
    ./scripts/stop.sh
    ```

## Contributing
1. Currently, there is only one variable that can be tuned from the environment, i.e `UPSTREAM_URL`. Maybe we can add more if there is a use case
2. There might be more improvements that can be made to the template file for better performance
3. Build process is still manual, and I only target `nginx:latest`
4. Feel free to suggest more improvements. Pull requests are welcome!

# Credits
This image was inspired by the work of others, especially the `nginx` part.
TODO: I've lost the references to them, but will add them in when I remember.

# License
TODO: Help me pick a license!
