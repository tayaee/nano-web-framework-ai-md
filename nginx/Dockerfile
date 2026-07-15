FROM nginx:1.27-alpine
# Bake the config into the image instead of bind-mounting it at runtime.
# On Windows Docker Desktop, bind-mounting a single file (or a directory
# containing just one file) into /etc/nginx/conf.d has been observed to
# non-deterministically materialize as an empty/broken directory instead of
# the actual file ("pread() ... failed (21: Is a directory)"), crash-looping
# nginx. COPY at build time sidesteps that whole class of runtime mount race.
# The base image ships its own conf.d/default.conf (the "Welcome to nginx!"
# vhost). Unlike the old directory-mount (which replaced conf.d wholesale and
# implicitly hid it), COPY only adds our file alongside it -- and nginx loads
# conf.d/*.conf alphabetically, so default.conf (d < n) would win as the
# default server and shadow ours, serving the welcome page / 404s instead of
# our routes. Remove it explicitly.
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.conf
