#!/usr/bin/env python3

import requests
import argparse
import time
from influxdb import InfluxDBClient

tags = [
    'target',
    'orchestrator',
    'deployer',
    'gerrit',
]
results = [
    'status',
    'duration',
    'logs',
]

def countprevious(days, measurement, tags):
    print(tags)
    s=""
    for tag in tags:
        s += "{} =~ /^{}$/ and ".format(tag, tags[tag])
    query = "SELECT status FROM \"{}\" WHERE {} time >= now() - {}d".format(measurement, s, days)
    print(query)
    client = InfluxDBClient(database="monitoring")
    rs=client.query(query)
    points = list(rs.get_points())
    print(points)
    successcount = len([p for p in points if p['status'] == "SUCCESS"])
    return "{}/{}".format(successcount, len(points))

def splitdata(logdata):
    ret = []
    for tag in tags:
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
        logitem['last_success_count'] = countprevious(7, measurement, {key: logitem[key] for key in tags})
        print(logitem)
        r = requests.post(url="{}/{}".format(url, measurement), json=logitem)
        print(r)

def main():
    parser = argparse.ArgumentParser()
    for tag in tags:
        parser.add_argument(
            "--{}".format(tag), dest=tag,
            type=str, required=True
        )
    for result in results:
        parser.add_argument(
            "--{}".format(result), dest=result,
            type=str, required=True
        )

    parser.add_argument(
        "--url", dest="url", type=str,
        default="http://10.0.3.124:9880"
    )
    parser.add_argument(
        "--measurement", dest="measurement",
        type=str, default="Jenkins.pipeline"
    )
    args=parser.parse_args()
    if args.url[-1] == '/':
        args.url = args.url[:-1]
    logdata = {}
    points = tags+results
    for point in points:
        logdata[point] = getattr(args, point)
    logdata['timestamp'] = int(time.time())
    do_log(args.url, args.measurement, logdata)

if __name__ == "__main__":
    main()
