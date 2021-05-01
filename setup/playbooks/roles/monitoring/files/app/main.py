from flask import Flask, session, redirect, url_for, request, render_template
from flask_wtf import FlaskForm
from wtforms import TextAreaField, SubmitField, HiddenField
from wtforms.validators import DataRequired
import os, requests

class Config(object):
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'you-will-never-guess'

app = Flask(__name__)
app.config.from_object(Config)

class CommentForm(FlaskForm):
    comment = TextAreaField('Comment', validators=[DataRequired()])
    gerrit = HiddenField()
    patchset = HiddenField()
    back = HiddenField()
    submit = SubmitField('Put')

@app.route("/r/<path:dashboard>")
def fixorchestrator(dashboard):
    u = '/g/d/'+dashboard+'?'
    for k,v in request.args.items():
        if k == 'var-orchestrator':
            v = v.split(' ')[0]
        u += '{}={}'.format(k, v)+'&'
    return redirect(u)


@app.route("/c/", methods=('GET', 'POST'))
def comment():
    grafana_root = "/g/"
    referrer = request.headers.get("Referer")
    if not referrer:
        referrer = grafana_root
    if 'patchset' in request.args and 'gerrit' in request.args:
        patchset = request.args['patchset'].replace(" ", "+")
        gerrit = request.args['gerrit']
    else:
        return redirect(grafana_root)

    form = CommentForm(
        request.values,
        patchset=patchset,
        gerrit=gerrit,
        back=referrer
    )
    if form.validate_on_submit():
        requests.post(
            "http://fluentd:9880/comments",
            json = {
                "gerrit": gerrit,
                "patchset": patchset,
                "comment": form.comment.data
        })
        return redirect(form.back.data)
    return render_template('comment.html', form=form)

if __name__ == "__main__":
    # Only for debugging while developing
    app.run(host='0.0.0.0', debug=False, port=80)
