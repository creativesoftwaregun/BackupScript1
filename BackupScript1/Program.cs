using System;
using System.IO;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Linq;
using System.Text.RegularExpressions;
using System.Diagnostics;

using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Management.Sdk.Sfc;
using Microsoft.SqlServer.Management.Common;

namespace BackupScript1
{
    // purpose: 
    //      perform backup
    //      get the script for a set of functions using a filter
    //      write each script to a file 
    // references:
    //      http://technet.microsoft.com/en-us/library/ms162153.aspx
    //      http://www.codeproject.com/Tips/639743/Versioning-your-Database-on-a-Budget-with-Csharp-a
                     
    class Program
    {
        const string objList = "ObjList.txt";
        static DisplayMessage displayMessage = new DisplayMessage(ConsoleColor.Green, ConsoleColor.Black);

        static dbInfo dbInfo;

        static void Main(string[] args)
        {

            try
            {
                if (!isArgsOk(args)) return; // abort if true

                dbInfo = new dbInfo(args[0], args[1], args[2]);

                new Work(dbInfo, objList, displayMessage).backupScript();
                displayMessage.Display(new string[] { "\n", "Success" } );
            }
            catch(Exception exc)
            {
                displayMessage.Display(new string[] { "---------------------", 
                    "\nException message: ",  exc.Message , "\nStack trace: ", exc.StackTrace.ToString() });
            }

        }

        static bool isArgsOk(string[] args)
        {
            if (args.Length == 0 || args.Count(x => string.IsNullOrEmpty(x))>0)
            {
                displayReadme();
                return false;
            }
            return true;
        }

        static void displayReadme()
        {
            string[] msg = new string[] { "\n", "Usage:", "\tBackupScript1.exe <data source> <database name> <scripts folder>", "\n" };
            displayMessage.Display(msg);
        }

    }

    class dbInfo
    {
        public string dataSource { get; private set; }
        public string db { get; private set; }
        public string scriptsFolder { get; private set; }

        public dbInfo(string p_DataSource, string p_Db, string p_ScriptsFolder)
        {
            dataSource = p_DataSource;
            db = p_Db;
            scriptsFolder = p_ScriptsFolder;
        }
    }

    class DisplayMessage
    {
        ConsoleColor oldForeColor;
        ConsoleColor oldBackgroundColor;

        delegate void AfterDisplayDelegate();
        AfterDisplayDelegate AfterDisplayEvent;

        public DisplayMessage(ConsoleColor p_ForeColor, ConsoleColor p_BackgroundColor)
        {
            setColor(p_ForeColor, p_BackgroundColor);
            oldForeColor = Console.ForegroundColor;
            oldBackgroundColor = Console.BackgroundColor;
            AfterDisplayEvent += new AfterDisplayDelegate(restoreColor);
        }

        private void restoreColor()
        {
            Console.ForegroundColor = oldForeColor;
            Console.BackgroundColor = oldBackgroundColor;
        }

        public void setColor(ConsoleColor p_ForeColor, ConsoleColor p_BackgroundColor)
        {
            Console.ForegroundColor = p_ForeColor;
            Console.BackgroundColor=p_BackgroundColor;
        }

        public void Display(string[] p_Msg)
        {
            foreach (string i in p_Msg)
            {
                Console.WriteLine(i);
            }
            if (AfterDisplayEvent != null)
            {
                AfterDisplayEvent();
            }
        }

        public void Display(string p_Msg)
        {
            Console.WriteLine(p_Msg);
            if (AfterDisplayEvent != null)
            {
                AfterDisplayEvent();
            }
        }
    }

    class Work
    {
        DisplayMessage displayMessage;

        dbInfo dbInfo { get; set; }
        string dbObjListFile { get; set; }

        Server server { get; set; } // target server
        Database db { get; set; } // target db
        List<string> dbObjList { get; set; } // list of db object names in text file
        
        public Work(dbInfo p_DbInfo, string p_DbObjListFile, DisplayMessage p_DisplayMessage)
        {
            dbInfo = p_DbInfo;
            dbObjListFile = p_DbObjListFile;
            displayMessage = p_DisplayMessage;
        }

        public void backupScript()
        {
            // windows authentication
            server = new Server(dbInfo.dataSource);
            server.ConnectionContext.LoginSecure = true;
            server.ConnectionContext.Connect();

            db = server.Databases[dbInfo.db] as Database;
            // abort if database cannot be resolved
            if (!isDbOk(db)) return;

            getDbObjList(); // get list of db objects from text file

            writeStoredProcedures(); // generate sp
            writeFunctions(); // generate functions

            if (server.ConnectionContext.IsOpen)
                server.ConnectionContext.Disconnect();
        }

        void getDbObjList()
        {
            dbObjList = openTextFileList();
        }

        void writeStoredProcedures()
        {
            var spList= db.StoredProcedures.Cast<StoredProcedure>();
            var listToScriptBackup = spList.Where(x => dbObjList.Contains(x.Name));

            foreach (StoredProcedure i in listToScriptBackup)
            {
                writeToFile(getScripter(), i.Urn, i.Name, dbInfo.scriptsFolder);
            }
        }

        void writeFunctions()
        {
            var functionList = db.UserDefinedFunctions.Cast<UserDefinedFunction>();
            var listToScriptBackup = functionList.Where(x => dbObjList.Contains(x.Name));

            foreach (UserDefinedFunction i in listToScriptBackup)
            {
                writeToFile(getScripter(), i.Urn, i.Name, dbInfo.scriptsFolder);
            }
        }

        void writeToFile(Scripter p_Scripter, Urn p_Urn, string p_Name, string p_ScriptsFolder)
        {
            StringCollection scriptCollection = p_Scripter.Script(new Urn[] { p_Urn });
            List<string> scriptLines= scriptCollection.Cast<string>().ToList();
            File.WriteAllLines(Path.Combine(p_ScriptsFolder, string.Format("{0}.sql", p_Name)), scriptLines);
        }

        Scripter getScripter()
        {
            Debug.Assert(server != null);

            Scripter retVal = new Scripter(server);
            retVal.Options.ScriptDrops = false;
            retVal.Options.WithDependencies = false; // important flag
            retVal.Options.Indexes = true;
            retVal.Options.DriAllConstraints = false; // important flag
            retVal.Options.NoCommandTerminator = true;
            retVal.Options.AllowSystemObjects = true;
            retVal.Options.Permissions = false;
            retVal.Options.SchemaQualify = true;
            retVal.Options.AnsiFile = true;
            retVal.Options.DriIndexes = true;
            retVal.Options.DriClustered = true;
            retVal.Options.DriNonClustered = true;
            retVal.Options.NonClusteredIndexes = true;
            retVal.Options.ClusteredIndexes = true;
            retVal.Options.FullTextIndexes = true;
            retVal.Options.EnforceScriptingOptions = true;

            return retVal;
        }

        bool isDbOk(Database p_Db)
        {
            if (p_Db == null) // abort
            {
                displayMessage.Display(new string[] { "\n", "Cannot resolve database.", "\n" });
                return false;
            }
            return true;
        }

        // note: encountered a problem when using split on string
        List<string> openTextFileList()
        {
            var retVal = new List<string>();
            using (StreamReader s = File.OpenText(dbObjListFile)) // UTF-8
            {
                while (!s.EndOfStream)
                {
                    retVal.Add(s.ReadLine()); 
                }
            }

            return retVal;
        }
    }
}
