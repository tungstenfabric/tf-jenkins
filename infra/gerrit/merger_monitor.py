import time


DELAY = 10


# to be run on nexus to avoid issues with credentials


class Checker():

    def get_last_merge(self):
        # run query on gerrit and returns latest merge from master branch of tungstenfabric projects
        pass

    def get_new_merges(self, last_merge):
        # returns list of latest merges since last_merge. sort by time.
        pass

    def update_tag(self, last_merge):
        # combine tag in a same way as main.groovy and stores it in logs folder which is local 
        pass


def main():
    # TODO: subscribe to stream and wait for events
    checker = Checker()
    last_merge = checker.get_last_merge()
    while True:
        new_merges = checker.get_new_merges(last_merge)
        if new_merges:
            checker.update_tag(new_merges[-1])
            last_merge = new_merges[-1]
        time.sleep(DELAY)


if __name__ == "__main__":
    main()
