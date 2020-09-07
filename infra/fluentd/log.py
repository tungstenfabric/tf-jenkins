#!/usr/bin/env python3

import requests
import argparse
import time

def splitdata(logdata):
  ret = []
  for key in logdata:
    datalist = logdata[key].split(',')
    if len(datalist) > 1:
        for d in datalist:
            logcopy = logdata.copy()
            logcopy[key] = d
            ret.append(l)
        break
  if len(ret) > 1:
      splittedret = []
      for r in ret:
          splittedret.extend(splitdata(r))
      ret = splittedret
  else:
      ret = [logdata,]

  return ret

def do_log(url, logdata):
    loglist = splitdata(logdata)
    for logitem in loglist:
        # No need to check response status code, workspace is a subject to wipe out
        # If data can't be submitted at the moment, it'll be dropped out
        r = requests.post(url=url, json=logitem)

def main():
    keys = [
        'target',
        'orchestrator',
        'deployer',
        'gerrit',
        'status',
    ]
    parser = argparse.ArgumentParser()
    for key in keys:
        parser.add_argument(
            "--{}".format(key), dest=key,
            type=str, required=True
        )
    parser.add_argument(
        "--url", dest="url", type=str,
        default="http://10.0.3.124:9880/"
    )
    parser.add_argument(
        "--measurement", dest="measurement",
        type=str, default="Jenkins.pipeline"
    )
    args=parser.parse_args()
    if args.url[-1] == '/':
        args.url = args.url[0:-1]
    logdata = {}
    for key in keys:
        logdata[key] = getattr(args, key)
    logdata['timestamp'] = int(time.time())
    url = '{}/{}'.format(args.url, args.measurement)
    do_log(url, logdata)



if __name__ == "__main__":
    main()
