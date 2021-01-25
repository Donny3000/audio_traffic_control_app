import os
import time
from flask import Flask


def create_app(test_config=None):
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY='dev',
        DATABASE=os.path.sep.join([app.instance_path, 'api.sqlite']),
    )

    if test_config is None:
        # Load the instance config, if it exists, when not testing
        app.config.from_pyfile('config.py', silent=True)
    else:
        # Load the test config if passed in
        app.config.from_mapping(test_config)

    # Ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    # A simple page that says hello
    @app.route('/hello')
    def hello():
        return "Hello, World!"
    
    @app.route('/time')
    def get_current_time():
        return {'time': time.time()}

    from . import db
    from . import auth
    db.init_app(app)
    app.register_blueprint(auth.bp)
    
    return app
