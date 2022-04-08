# treecheck

Windows command-line utility to compare the contents of two folders asynchronously.
First, the directory structure is stored in a database file. Then it compares
the content of this database file with the structure of the second directory.

With this utility, you can check if a remote directory is an exact mirror of 
a local directory. You just have to create the dbfile containing the local
directory structure on the first computer. Then copy the dbfile on the second
computer and run the comparison.

You can also use this utility to get all files an directories names that were
added or modified during an installation.
For example : you can create a dbfile containing your c:\windows structure.
Then launch your installer and finally run the comparison with the actual 
c:\windows (using -n switch) to get all  
```
Usage: 

First, check the source directory  :
treecheck.exe -s <source_dir> -f <datafile>.db [-l]
  -s <source_dir> : source dir to check
  -f <datafile>.db : source_dir hierarchy will be stored in this file for later comparisonded file or fetched file
  -l (optional,experimental) : enable Windows longpath support (>260 chars)

Then, compare with the destination directory :
treecheck.exe -d <dest_dir> -f <datafile>.db -o <output_logfile.csv> [-t] [-n] [-l]
  -d <dest_dir> : destination directory
  -f <datafile>.db : database file previously created, containing source_dir hierarchy
  -o <output_logfile.csv> : differences between <source_dir> and <dest_dir> will be written in this CSV file
  -t (optional) : also check for changes in files timestamps
  -n (optional) : check if <dest_dir> contains directories or files that are missing in <source_dir>.
  -l (optional,experimental) : enable Windows longpath support (>260 chars)
```

This program have been created by Cyril LAMY under the terms of the [GNU General Public License v3](http://www.gnu.org/licenses/gpl.html).


## Examples :

Creating the dbfile :

```
treecheck.exe -s "c:\data" -f data.db
```

Compare with the destination directory

```
treecheck.exe -d "c:\mirrors\data" -f data.db -o output.csv -t
```

CREDITS :
This program use the [SQLite database engine](https://www.sqlite.org/index.html).
