import functools
from flask import (
    Blueprint, flash, g, redirect, request, session, url_for
)
from werkzeug.security import check_password_hash, generate_password_hash
from api.db import get_db


bp = Blueprint('auth', __name__, url_prefix='/auth')

@bp.route('/user_login')
def user_create():
    pass


@bp.route('/user_login')
def user_login():
    pass


@bp.before_app_request
def load_logged_in_user():
    user_id = session.get('user_id')

    if user_id is None:
        g.user = None
    else:
        g.user = get_db().execute(
            'SELECT * FROM user WHERE id = ?', (user_id,)
        ).fetchone()


@bp.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('index'))
