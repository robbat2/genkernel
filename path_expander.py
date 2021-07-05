#!/usr/bin/env python3

import os
import sys

def main(argv):
	if len(argv) != 1:
		print(
			"%s expects exactly one argument but %s were given!"
			% (os.path.basename(__file__), len(argv)),
			file=sys.stderr
		)
		sys.exit(1)

	print(os.path.expanduser(argv[0]))

if __name__ == "__main__":
	main(sys.argv[1:])
