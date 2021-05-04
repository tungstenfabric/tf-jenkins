#!/usr/bin/env python3

import requests
import argparse
import sys
import subprocess

tags = [
    'target',
    'orchestrator',
    'deployer',
    'gerrit',
]
results = [
    'status',
    'duration',
    'started',
    'patchset',
    'logs',
]

def countprevious(days, measurement, logitem):
    taglist = {key: logitem[key] for key in tags}
    try:
        import influxdb
    except:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'influxdb'])
        import influxdb

    clause=""
    for tag in taglist:
        clause += "{} =~ /^{}$/ and ".format(tag, taglist[tag])
    query = "SELECT status FROM \"{}\" WHERE {} time >= now() - {}d".format(measurement, clause, days-1)
    client = influxdb.InfluxDBClient(host="10.0.3.124", database="monitoring")
    res=client.query(query)
    points = list(res.get_points())
    successcount = len([p for p in points if p['status'] == "SUCCESS"])
    if logitem['status'] == "SUCCESS":
        successcount += 1
    return "{}/{}".format(successcount, len(points)+1)

def splitdata(logdata):
    ret = []
    for tag in logdata.keys():
        datalist = logdata[tag].split(',')
        if len(datalist) > 1:
            for d in datalist:
                logcopy = logdata.copy()
                logcopy[tag] = d
                ret.append(logcopy)
            break
    if len(ret) > 1:
        splittedret = []
        for r in ret:
            splittedret.extend(splitdata(r))
        ret = splittedret
    else:
        ret = [logdata,]

    return ret

def do_log(url, measurement, logdata):
    loglist = splitdata(logdata)
    for logitem in loglist:
        # No need to check response status code, workspace is a subject to wipe out
        # If data can't be submitted at the moment, it'll be dropped out
        logitem['duration'] = "{}h {}m {}s".format(
            int(int(logitem['duration']) / (3600*1000)),
            int(int(logitem['duration']) / (1000*60) % 60),
            int(int(logitem['duration']) % (60*1000) / 1000)
        )
        try:
            logitem['last_success_count'] = countprevious(7, measurement, logitem)
        except:
            pass
        r = requests.post(url="{}/{}".format(url, measurement), json=logitem)

def main():
    parser = argparse.ArgumentParser()
    for tag in tags:
        parser.add_argument(
            "--{}".format(tag), dest=tag,
            type=str
        )
    for result in results:
        parser.add_argument(
            "--{}".format(result), dest=result,
            type=str
        )

    parser.add_argument(
        "--url", dest="url", type=str, required=True
    )
    parser.add_argument(
        "--measurement", dest="measurement",
        type=str, default="Jenkins.pipeline"
    )
    args=parser.parse_args()
    if args.url[-1] == '/':
        args.url = args.url[:-1]
    logdata = {}
    keys = tags+results
    for key in keys:
        value = getattr(args, key)
        if value:
            logdata[key] = value

    do_log(args.url, args.measurement, logdata)

if __name__ == "__main__":
    main()
