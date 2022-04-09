program treecheck;

{$mode objfpc}{$H+}

{

    treecheck -- Compare the contents of two folders

    Copyright (C) 2022  Cyril LAMY

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, SQLDB, SQLite3Conn, LazUtils, fileutil, LazFileUtils,LazUTF8;

const treecheckversion='1.0';

type
  TMyApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

var
  sqlite3: TSQLite3Connection;
  dbTrans: TSQLTransaction;
  dbQuery: TSQLQuery;
  longpath,checktimestamp,checkfornew: boolean;


{ TMyApplication }



function GetFileSize(filename : String) : Int64;
begin
  if (length(filename)>260) and (longpath=true) then filename:='\\?\'+filename;
  GetFileSize:=FileSize(filename);
end;


function ExtractRelativePathname(Dirname,Path:string) : string;
begin
  Dirname:=IncludeTrailingPathDelimiter(DirName);
  if UTF8Pos(Dirname,Path)=1 Then
  begin
    Delete(Path,1,length(Dirname));
  end;
  ExtractRelativePathname:=Path;
end;

procedure checksource(Dirname, Databasename: string);

var
  Files: TStringList;
  cnt,filesize,timestmp: Longint;
  S : TDateTime;
  warninglongfilename: boolean;

begin

  Dirname:=IncludeTrailingPathDelimiter(DirName);
  warninglongfilename:=false;

  Writeln('Initializing database ',Databasename,' ...');
  sqlite3:= TSQLite3Connection.Create(nil);
  dbTrans:= TSQLTransaction.Create(nil);
  dbQuery:= TSQLQuery.Create(nil);
  sqlite3.Transaction:= dbTrans;
  dbTrans.Database:= sqlite3;
  dbQuery.Transaction:= dbTrans;
  dbQuery.Database:= sqlite3;;
  sqlite3.DatabaseName := Databasename;
  sqlite3.HostName     := 'localhost';
  sqlite3.CharSet      := 'UTF8';

  // if database exists, delete it
  if FileExists(Databasename) then begin
    if not(deletefile(Databasename)) then begin
       writeln('Error: ',Databasename,' exists and is not writable ');
       Exit;
    end;
  end;

  // Open DB
  sqlite3.Open;

  // Create table and indexes
  sqlite3.ExecuteDirect('CREATE TABLE dirtree ( id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT , filename TEXT , type INTEGER, size INTEGER, timestamp TEXT )');
  sqlite3.ExecuteDirect('CREATE INDEX idx_filename ON "dirtree"( filename )');
  sqlite3.ExecuteDirect('CREATE INDEX idx_type ON "dirtree"( type )');
  sqlite3.ExecuteDirect('CREATE INDEX idx_id ON "dirtree"( id )');

  // Search for files
  Writeln('Listing directories ...');
  Files:=FindAllDirectories(Dirname, true);
  try
    if (Files.Count>0) then begin
      for cnt:=0 to (Files.Count-1) do begin
        if (longpath=false) and (length(Files[cnt])>260) then warninglongfilename:=true;
        if not DirectoryExists(IncludeTrailingPathDelimiter(Files[cnt])+'.') then begin
          writeln('[WARNING] : Directory ',Files[cnt],' is not readable, sub-content may be missing in db');
        end;
        dbQuery.SQL.Clear;
        dbQuery.SQL.Text:='INSERT INTO dirtree (filename,type) VALUES (:filename,:filetype)';
        dbQuery.Params.ParamByName('filetype').AsInteger:= 1;
        dbQuery.Params.ParamByName('filename').AsString:=ExtractRelativePathname(Dirname,Files[cnt]);
        dbQuery.ExecSQL;
      end;
    end;
  finally
    Files.free;
  end;
  dbTrans.Commit;
  Writeln('Listing files ...');
  Files:=FindAllFiles(Dirname, '*.*', true);
  try
    if (Files.Count>0) then begin
      for cnt:=0 to (Files.Count-1) do begin
        if (longpath=false) and (length(Files[cnt])>260) then warninglongfilename:=true;
        filesize:=GetFileSize(Files[cnt]);
        if filesize=-1 then begin
          writeln('[WARNING] : Unable to get the size of file ',Files[cnt]);
        end;
        timestmp:=FileAge(Files[cnt]);
        dbQuery.SQL.Clear;
        dbQuery.SQL.Text:='INSERT INTO dirtree (filename,type,size,timestamp) VALUES (:filename,:filetype,:filesize,:timestamp)';
        dbQuery.Params.ParamByName('filetype').AsInteger:= 2;
        dbQuery.Params.ParamByName('filename').AsString:=ExtractRelativePathname(Dirname,Files[cnt]);
        dbQuery.Params.ParamByName('filesize').AsLargeInt:=filesize;
        if timestmp<>-1 then begin
          S:=FileDateTodateTime(timestmp);
          dbQuery.Params.ParamByName('timestamp').AsString:=lowercase(FormatDateTime('yyyy-mm-dd hh:nn:ss',S));
        end;
        dbQuery.ExecSQL;
      end;
    end;
  finally
    Files.free;
  end;
  dbTrans.Commit;
  dbQuery.Close;
  dbQuery.Destroy;
  dbTrans.Destroy;
  sqlite3.Close;
  sqlite3.Destroy;
  if warninglongfilename=true then writeln('[ WARNING ] some filenames exceed 260 characters. Try -l switch to enable longpath support');
  writeln('Database successfully created');
end;

procedure checkdest(Dirname, Databasename, Outfile: string);
var logfile: TextFile;
    filename,filestmp: string;
    filetype: integer;
    timestmp,filesize,newsize,cnt: longint;
    S : TDateTime;
    Files: TStringList;
    warninglongfilename: boolean;

begin

  Dirname:=IncludeTrailingPathDelimiter(DirName);

  // Open logfile for writing
  AssignFile(logfile, Outfile);
  try
     rewrite(logfile);
  except
    begin
      writeln('Error: Cannot open',Outfile,' for writing');
      Exit;
    end;
  end;
  writeln(logfile,'"ERROR TYPE";"FILENAME";"SOURCE TIMESTAMP";"DESTINATION TIMESTAMP";');

  // Init DB
  sqlite3:= TSQLite3Connection.Create(nil);
  dbTrans:= TSQLTransaction.Create(nil);
  dbQuery:= TSQLQuery.Create(nil);
  sqlite3.Transaction:= dbTrans;
  dbTrans.Database:= sqlite3;
  dbQuery.Transaction:= dbTrans;
  dbQuery.Database:= sqlite3;;
  sqlite3.DatabaseName := Databasename;
  sqlite3.HostName     := 'localhost';
  sqlite3.CharSet      := 'UTF8';

  if not FileExists(Databasename) then begin
    writeln('Error: database ',Databasename,' does not exists');
    Exit;
  end;

  try
   sqlite3.Open;
   dbQuery.SQL.Text:='SELECT * FROM dirtree';
   dbQuery.Open;
   if (dbQuery.RecordCount<1) then begin
     writeln('Error: database is empty');
     Exit;
   end;
   dbQuery.Close;
  except
    begin
      writeln('Error: ',Databasename,' is not a database file !');
      Exit;
    end;
  end;


  // Perform the check
  dbQuery.SQL.Text:='SELECT * FROM dirtree ORDER BY filename';
  dbQuery.Open;

  writeln('Checking for mismatching files or directories, logging changes to ',Outfile);
  cnt:=0;
  warninglongfilename:=false;

  if (dbQuery.RecordCount>0) then
  begin
    while (not (dbQuery.EOF))  do begin
        filename:=Dirname+dbQuery.FieldByName('filename').AsString;
        if (longpath=false) and (length(filename)>260) then warninglongfilename:=true;
        if (length(filename)>260) and (longpath=true) then filename:='\\?\'+filename;
        filetype:=dbQuery.FieldByName('type').AsInteger;
        if filetype=2 then filesize:=dbQuery.FieldByName('size').AsLongint
           else filesize:=0;
        if filetype=2 then filestmp:=dbQuery.FieldByName('timestamp').AsString
           else filestmp:='';
        if filetype=1 then begin
          // Check if directory exists
          If Not DirectoryExists(filename) then begin
            write(logfile,'"[ MISSING DIR ] ";"');
            write(logfile,filename);
            writeln(logfile,'";');
          end;
        end;
        if filetype=2 then begin
          // Check if file exists
          If Not FileExists(filename) then begin
            write(logfile,'"[ MISSING FILE ] ";"');
            write(logfile,filename);
            if (filestmp<>'-1') and (filestmp<>'') then begin
              write(logfile,'";"');
              write(logfile,filestmp);
            end;
            writeln(logfile,'";')
          end
          else
          begin
             newsize:=GetFileSize(filename);
             if (newsize<>-1) and (filesize<>-1) then begin
                if newsize<>filesize then
                begin
                  write(logfile,'"[ SIZE MISMATCH ] ";"');
                  write(logfile,filename);
                  if (filestmp<>'-1') and (filestmp<>'') then begin
                    write(logfile,'";"');
                    write(logfile,filestmp);
                    timestmp:=FileAge(filename);
                    if timestmp<>-1 then begin
                      S:=FileDateTodateTime(timestmp);
                      write(logfile,'";"');
                      write(logfile,FormatDateTime('yyyy-mm-dd hh:nn:ss',S));
                    end;
                  end;
                  writeln(logfile,'";')
                end;
             end;
             if checktimestamp=true then begin
                timestmp:=FileAge(filename);
                if timestmp<>-1 then begin
                   S:=FileDateTodateTime(timestmp);
                   if (filestmp<>'') and (lowercase(FormatDateTime('yyyy-mm-dd hh:nn:ss',S))<>filestmp) then
                   begin
                     write(logfile,'"[ TIMESTAMP MISMATCH ] ";"');
                     write(logfile,filename);
                      if (filestmp<>'-1') and (filestmp<>'') then begin
                        write(logfile,'";"');
                        write(logfile,filestmp);
                        timestmp:=FileAge(filename);
                        if timestmp<>-1 then begin
                          S:=FileDateTodateTime(timestmp);
                          write(logfile,'";"');
                          write(logfile,FormatDateTime('yyyy-mm-dd hh:nn:ss',S));
                        end;
                      end;
                     writeln(logfile,'";')
                   end;
                end;
             end;
          end;
        end;
        dbQuery.Next;
        inc(cnt);
    end;
  end;

  if checkfornew=true then begin
    writeln('Checking for new directories, logging to ',Outfile,'.This may take a while ...');

    // Searching for new dirs
    Files:=FindAllDirectories(Dirname, true);
    try
      if (Files.Count>0) then begin
        for cnt:=0 to (Files.Count-1) do begin
          if (longpath=false) and (length(Files[cnt])>260) then warninglongfilename:=true;
          if not DirectoryExists(IncludeTrailingPathDelimiter(Files[cnt])+'.') then begin
            writeln('[WARNING] : Directory ',Files[cnt],' is not readable, sub-content cannot be analyzed');
          end;
          dbQuery.Close;
          dbQuery.SQL.Clear;
          dbQuery.SQL.Text:='SELECT id FROM dirtree WHERE filename=:filename AND type=1';
          dbQuery.Params.ParamByName('filename').AsString:=ExtractRelativePathname(Dirname,Files[cnt]);
          dbQuery.Open;
          if (dbQuery.RecordCount<1) then
          begin
            write(logfile,'"[ NEW DIR ] ";"');
            write(logfile,Files[cnt]);
            writeln(logfile,'";');
          end
        end;
      end;
    finally
      Files.free;
    end;

    // Searching for new files
    writeln('Checking for new files, logging to ',Outfile,'.Time to take a break ...');
    Files:=FindAllFiles(Dirname, '*.*', true);
    try
      if (Files.Count>0) then begin
        for cnt:=0 to (Files.Count-1) do begin
          if (longpath=false) and (length(Files[cnt])>260) then warninglongfilename:=true;
          dbQuery.Close;
          dbQuery.SQL.Clear;
          dbQuery.SQL.Text:='SELECT id FROM dirtree WHERE filename=:filename AND type=2';
          dbQuery.Params.ParamByName('filename').AsString:=ExtractRelativePathname(Dirname,Files[cnt]);
          dbQuery.Open;
          if (dbQuery.RecordCount<1) then
          begin
            write(logfile,'"[ NEW FILE ] ";"');
            write(logfile,Files[cnt]);
            writeln(logfile,'";')
          end;
        end;
      end;
    finally
      Files.free;
    end;
  end;

  // close all
  CloseFile(logfile);
  dbQuery.Close;
  dbQuery.Destroy;
  dbTrans.Destroy;
  sqlite3.Close;
  sqlite3.Destroy;
  if warninglongfilename=true then writeln('[ WARNING ] some filenames exceed 260 characters. Try -l switch to enable longpath support');
  writeln('Logfile written, ',inttostr(cnt),' entries processed');
end;

procedure TMyApplication.DoRun;
var
  ErrorMsg: String;
  Sourcecheck,Destcheck: boolean;
  Dirname, Databasename, Outfile: string;

begin
  // quick check parameters
  ErrorMsg:=CheckOptions('hsdfotnl', 'help');
  if ErrorMsg<>'' then begin
    Writeln('Error: Bad arguments');
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h', 'help') then begin
    WriteHelp;
    Terminate;
    Exit;
  end;

  Sourcecheck:=false;
  Destcheck:=false;
  Dirname:='';
  Outfile:='';
  Databasename:='';
  checktimestamp:=false;
  checkfornew:=false;
  longpath:=false;

  // Check if -s is used
  if HasOption('s') then begin
    Dirname:=Self.GetOptionValue('s');
    if Dirname='' then begin
       writeln('Error: -s need source_dir as argument');
       Terminate;
       Exit;
    end;
    If Not DirectoryExists(Dirname) then begin
       writeln('Error: ',Dirname,' is not a directory !');
       Terminate;
       Exit;
    end;
    Sourcecheck:=true;
  end;

  // Check if -d is used
  if HasOption('d') then begin
    Dirname:=Self.GetOptionValue('d');
    if Dirname='' then begin
       writeln('Error: -d need dest_dir as argument');
       Terminate;
       Exit;
    end;
    If Not DirectoryExists(Dirname) then begin
       writeln('Error: ',Dirname,' is not a directory !');
       Terminate;
       Exit;
    end;
    Destcheck:=true;
  end;

  // Check coherency
  if (Sourcecheck=false) and (Destcheck=false) then begin
    writeln('Error: at least -s or -d should be specified');
    writeln('       use -h for help');
    Terminate;
    Exit;
  end;

  if (Sourcecheck=true) and (Destcheck=true) then begin
    writeln('Error: -s and -d cannot be specified simultaneously');
    writeln('       use -h for help');
    Terminate;
    Exit;
  end;

  // Check for -f
  if HasOption('f') then begin
    Databasename:=Self.GetOptionValue('f');
    if Databasename='' then begin
       writeln('Error: -f need <datafile>.db as argument');
       Terminate;
       Exit;
    end;
  end
  else begin
    writeln('Error: you must specify a database name with -f <datafile>.db');
    Terminate;
    Exit;
  end;

  // Check for -l
   if HasOption('l') then longpath:=true;

  // Check for -o if -d is set
  if (Destcheck=true) then begin
     if HasOption('t') then checktimestamp:=true;
     if HasOption('n') then checkfornew:=true;
     if HasOption('o') then begin
       Outfile:=Self.GetOptionValue('o');
       if Outfile='' then begin
          writeln('Error: -o need <output_logfile.txt> as argument');
          Terminate;
          Exit;
       end
     end
     else begin
       writeln('Error: you must specify an output file name with -o <output_logfile.csv>');
       Terminate;
       Exit;
     end;
  end;

  // Run the specified subroutine

  if (Sourcecheck=true) then checksource(Dirname,Databasename);
  if (Destcheck=true) then checkdest(Dirname,Databasename,Outfile);

  // stop program loop
  Terminate;
end;

constructor TMyApplication.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
end;

destructor TMyApplication.Destroy;
begin
  inherited Destroy;
end;

procedure TMyApplication.WriteHelp;
begin
  { Display command line help }

  writeln('TreeCheck v',treecheckversion,' -- Compare the contents of two folders');
  writeln('Copyright (C) 2022  Cyril LAMY');
  writeln('This program comes with ABSOLUTELY NO WARRANTY.');
  writeln('This is free software, and you are welcome to redistribute it');
  writeln('under certain conditions. Visit https://www.gnu.org/licenses/gpl-3.0.html');
  writeln('for more details.');
  writeln();
  writeln('Usage : ');
  writeln('First, check the source directory  : ');
  writeln(ExeName,' -s <source_dir> -f <datafile>.db [-l]');
  writeln('  -s <source_dir> : source dir to check');
  writeln('  -f <datafile>.db : source_dir hierarchy will be stored in this file for later comparison');
  writeln('  -l : enable windows long paths support (>260 chars)');
  writeln();
  writeln('Then, compare with the destination directory :');
  writeln(ExeName,' -d <dest_dir> -f <datafile>.db -o <output_logfile.csv> [-t] [-n] [-l]');
  writeln('  -d <dest_dir> : destination directory');
  writeln('  -f <datafile>.db : database file previously created, containing source_dir hierarchy');
  writeln('  -o <output_logfile.csv> : differences between <source_dir> and <dest_dir> will be written in this CSV file ');
  writeln('  -t (optional) : also check for changes in files timestamps');
  writeln('  -n (optional) : check if <dest_dir> contains directories or files that are missing in <source_dir>.');
  writeln('  -l : enable windows long paths support (>260 chars)');
  writeln();
  writeln('-h : print this help');
  writeln();
end;

var
  Application: TMyApplication;
begin
  Application:=TMyApplication.Create(nil);
  Application.Title:='Treecheck';
  Application.Run;
  Application.Free;
end.

