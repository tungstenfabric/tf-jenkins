import os
from flask import Flask, session, redirect, url_for, request, render_template
from flask_wtf import FlaskForm
from wtforms import TextAreaField, SubmitField, HiddenField
# from wtforms.widgets import TextArea
from wtforms.validators import DataRequired
import psycopg2

class Config(object):
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'you-will-never-guess'

app = Flask(__name__)
app.config.from_object(Config)

class CommentForm(FlaskForm):
    comment = TextAreaField('Comment', validators=[DataRequired()])
    patchset = HiddenField()
    back = HiddenField()
    submit = SubmitField('Put')

@app.route("/r/<path:dashboard>")
def fixorchestrator(dashboard):
    u = '/d/'+dashboard+'?'
    for k,v in request.args.items():
        if k == 'var-orchestrator':
            v = v.split(' ')[0]
        u += '{}={}'.format(k, v)+'&'
    return redirect(u)


@app.route("/c/", methods=('GET', 'POST'))
def comment():
    sql = "UPDATE pipelines SET comment ='{}' WHERE patchset = '{}'"

    referrer = request.headers.get("Referer")
    if not referrer:
        referrer = "/"
    patchset = ""
    for k,v in request.args.items():
        if k == 'patchset':
            patchset = v
            break
    if not patchset:
        return redirect("/")
    patchset = patchset.replace(" ", "+")
    print(patchset)
    form = CommentForm(request.values, patchset=patchset, back=referrer)
    if form.validate_on_submit():
        try:
            conn = psycopg2.connect(
                host="postgres",
                dbname="postgres",
                user="postgres",
                password="postgres"
                )
            cur = conn.cursor()
            patchset = form.patchset.data.replace(" ", "+")
            print(sql.format(form.comment.data, patchset))
            cur.execute(sql.format(form.comment.data, patchset))
            conn.commit()
            cur.close()
        except (Exception, psycopg2.DatabaseError) as error:
            print(error)
        finally:
            if conn is not None:
                conn.close()
        return redirect(form.back.data)
    return render_template('comment.html', form=form)

if __name__ == "__main__":
    # Only for debugging while developing
    app.run(host='0.0.0.0', debug=False, port=80)
