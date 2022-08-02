# config priorities see: https://docs.gunicorn.org/en/latest/configure.html
# config options see: https://docs.gunicorn.org/en/latest/settings.html

bind=["0.0.0.0:8043"]

workers=2
worker_class="gevent"

# see: https://www.joelsleppy.com/blog/gunicorn-application-preloading/
preload_app = True

# write to console
accesslog = "-"

wsgi_app = "main:app"