#include <MsgBoxConstants.au3>
#include <FileConstants.au3>
#include <InetConstants.au3>
#include <WinAPIFiles.au3>
#include <Date.au3>
#include <Array.au3>
#include <File.au3>

If $CmdLine[0] = 0 Then
	Exit
EndIf

Global $sPROJECT_NAME = $CmdLine[1]

;~ ---------------------
; Lock

Local $lock_file_path = @HomeDrive & @HomePath & "\docker-app\" & $sPROJECT_NAME & ".lock"

If FileExists($lock_file_path) Then
    ; Get the creation time of the file in seconds since epoch
    Local $file_creation_time = FileGetTime($lock_file_path, $FT_MODIFIED, 1)
    Local $current_time = _NowCalc() ; Get the current time in seconds since epoch
    Local $timeout_seconds = 60

    If $current_time - $file_creation_time > $timeout_seconds Then
        FileDelete($lock_file_path)
    EndIf
EndIf

;~ ------------------------
; Add queue

If FileExists($lock_file_path) Then
    Local $lines
	If _FileReadToArray($lock_file_path, $lines) Then
		Local $found = False

		For $i = 1 To $lines[0]
			If StringStripWS($lines[$i], 8) = StringStripWS($parameters, 8) Then
				ConsoleWrite("Parameters already exist in the lock file. Exiting..." & @CRLF)
				Exit
			EndIf
		Next

		_FileWriteToLine($lock_file_path, $lines[0] + 1, $parameters, 1)
		ConsoleWrite("Added queue " & $parameters & @CRLF)
		Exit
	Else
		If FileExists($lock_file_path) Then
			FileDelete($lock_file_path)
		EndIf
	EndIf
Else
    ConsoleWrite("Lock file does not exist." & @CRLF)
EndIf

;~ ---------------------
; create lock
; Open the file in write mode to create or update the access and modification times
Global $fileHandle = FileOpen($lock_file_path, $FO_OVERWRITE)

; Close the file handle
FileClose($fileHandle)

; Function to get the directory path from a file path
Func GetDirPath($sFilePath)
    Local $iLastBackslash = StringInStr($sFilePath, "\", 0, -1) ; Find the last occurrence of '\'
    If $iLastBackslash > 0 Then
        Return StringLeft($sFilePath, $iLastBackslash - 1)
    EndIf
    ; If no backslash is found, assume the file path is just a filename
    Return @ScriptDir
EndFunc

;~ ---------------------

;~ MsgBox($MB_SYSTEMMODAL, "Title", "This message box will timeout after 10 seconds or select the OK button.", 10)
Local $sProjectFolder = @HomeDrive & @HomePath & "\docker-app\" & $sPROJECT_NAME
Local $inited = 1
If Not FileExists($sProjectFolder) then
	$inited = 0
	MsgBox($MB_SYSTEMMODAL, $sPROJECT_NAME, "Before executing the script, it is recommended to either disable your antivirus software or add this script to the antivirus software's whitelist to prevent any unintended issues.", 30)
EndIf

Local $sWorkingDir = @WorkingDir
Local $sScriptDir = GetDirPath($CmdLine[2])

;~ ---------------------

Local $result = 0

$result = ShellExecuteWait('WHERE', 'git', "", "open", @SW_HIDE)
If $result = 1 then
	If FileExists($lock_file_path) Then
	    FileDelete($lock_file_path)
	EndIf
	MsgBox($MB_SYSTEMMODAL, "Environment Setting", "Please install GIT.")
	ShellExecute("https://git-scm.com/downloads", "", "open", @SW_HIDE)
	Exit
EndIf

$result = ShellExecuteWait('WHERE', 'docker-compose', "", "open", @SW_HIDE)
If $result = 1 then
	If FileExists($lock_file_path) Then
	    FileDelete($lock_file_path)
	EndIf
	MsgBox($MB_SYSTEMMODAL, "Environment Setting", "Please install Docker Desktop.")
	ShellExecute("https://docs.docker.com/compose/install/", "", "open", @SW_HIDE)
	Exit
EndIf

$result = ShellExecuteWait('docker', 'version', "", "open", @SW_HIDE)
If $result = 1 then
	If FileExists($lock_file_path) Then
	    FileDelete($lock_file_path)
	EndIf
	MsgBox($MB_SYSTEMMODAL, "Environment Setting", "Please start Docker Desktop.")
	Exit
EndIf

;~ ---------------------

;Local $sProjectFolder = @TempDir & "\" & $sPROJECT_NAME

;~ MsgBox($MB_SYSTEMMODAL, FileExists($sProjectFolder), $sProjectFolder)
ShellExecuteWait("git", "config --global core.autocrlf false", "", "open", @SW_HIDE)
If Not FileExists($sProjectFolder) Then
	FileChangeDir(@HomeDrive & @HomePath & "\docker-app\")
	ShellExecuteWait("git", "clone https://github.com/pulipulichen/" & $sPROJECT_NAME & ".git")
	FileChangeDir($sProjectFolder)
Else
	FileChangeDir($sProjectFolder)
	ShellExecuteWait("git", "reset --hard", "", "open", @SW_HIDE)
	ShellExecuteWait("git", "pull --force", "", "open", @SW_HIDE)
EndIf

;~ ---------------------

Local $sProjectFolderCache = $sProjectFolder & ".cache"
If Not FileExists($sProjectFolderCache) Then
	DirCreate($sProjectFolderCache)
EndIf

$result = ShellExecuteWait("fc", '"' & $sProjectFolder & "\Dockerfile" & '" "' & $sProjectFolderCache & "\Dockerfile" & '"', "", "open", @SW_HIDE)
If $result = 1 then
	ShellExecuteWait("docker-compose", "build")
	FileCopy($sProjectFolder & "\Dockerfile", $sProjectFolderCache & "\Dockerfile", $FC_OVERWRITE)
EndIf

$result = ShellExecuteWait("fc", '"' & $sProjectFolder & "\package.json" & '" "' & $sProjectFolderCache & "\package.json" & '"', "", "open", @SW_HIDE)
If $result = 1 then
	ShellExecuteWait("docker-compose", "build")
EndIf

FileCopy($sProjectFolder & "\Dockerfile", $sProjectFolderCache & "\Dockerfile", $FC_OVERWRITE)
FileCopy($sProjectFolder & "\package.json", $sProjectFolderCache & "\package.json", $FC_OVERWRITE)

;~ =================================================================
;~ ?docker-compose-template.yml?????

Local $INPUT_FILE = 0

If FileExists($sProjectFolder & "\docker-build\image\docker-compose-template.yml") Then
  Local $fileContent = FileRead($sProjectFolder & "\docker-build\image\docker-compose-template.yml")
  If StringInStr($fileContent, "__INPUT__") Then
    $INPUT_FILE = 1
  EndIf
EndIf

;~ ---------------------

Local $PUBLIC_PORT = 0

Local $DOCKER_COMPOSE_FILE = $sProjectFolder &  "\docker-compose.yml"
If Not FileExists($DOCKER_COMPOSE_FILE) Then
  $DOCKER_COMPOSE_FILE = $sProjectFolder & "\docker-build\image\image\docker-compose-template.yml"
EndIf

If FileExists($DOCKER_COMPOSE_FILE) Then
  Local $fileContent = FileRead($DOCKER_COMPOSE_FILE)
  Local $pattern = "ports:"
  Local $lines = StringSplit($fileContent, @CRLF)

  Local $flag = False
  For $i = 1 To $lines[0]
      If StringInStr($lines[$i], $pattern) Then
          $flag = True
      EndIf

      If $flag Then
        Local $portMatch = StringRegExp($lines[$i], '"[0-9]+:[0-9]+"', 3)
        If IsArray($portMatch) Then
          Local $portSplit = StringSplit(StringTrimRight(StringTrimLeft($portMatch[0], 1), 1), ':')
          $PUBLIC_PORT = $portSplit[1]
          ExitLoop
        EndIf
      EndIf
  Next
EndIf

;~ ---------------------
;~ ????

Global $sFILE_EXT = "* (*.*)"

Local $sUseParams = true
Local $sFiles[]
If $INPUT_FILE = 1 Then
	If $CmdLine[0] = 0 Then
		$sUseParams = false
		Local $sMessage = "Select File"
		Local $sFileOpenDialog = FileOpenDialog($sMessage, $sScriptDir & "\", $sFILE_EXT , $FD_FILEMUSTEXIST + $FD_MULTISELECT)
		$sFiles = StringSplit($sFileOpenDialog, "|")
	EndIf
EndIf

;~ =================================================================
;~ ????

Func getCloudflarePublicURL()
	;ConsoleWrite("getCloudflarePublicURL"  & @CRLF)
    Local $dirname = $sScriptDir
    
    Local $cloudflareFailed = $dirname & "" & $sPROJECT_NAME & "\.cloudflare.failed"
    If FileExists($cloudflareFailed) Then
	    Return false
    EndIf

    Local $cloudflareFile = $dirname & "" & $sPROJECT_NAME & "\.cloudflare.url"
	;ConsoleWrite($cloudflareFile  & @CRLF)
		Local $timeout = 120 ; 60 seconds timeout
		Local $interval = 5 ; 5 seconds interval
		Local $elapsedTime = 0

		While $elapsedTime < $timeout
		    If FileExists($cloudflareFile) Then
			ConsoleWrite("Existed"  & @CRLF)
			Local $fileContent = FileRead($cloudflareFile)
			ConsoleWrite($fileContent  & @CRLF)
			If StringStripWS($fileContent, 1 + 2) <> "" Then
			   Return $fileContent
			EndIf
		    EndIf

		    Sleep($interval * 1000) ; Sleep for $interval seconds
		    $elapsedTime += $interval
		WEnd

		setCloudflareFailed()
		Return false
EndFunc

Func waitForDockerAppReady()
	;ConsoleWrite("getCloudflarePublicURL"  & @CRLF)
    Local $dirname = $sScriptDir
    
    Local $readyFile = $dirname & "" & $sPROJECT_NAME & "\.docker-web.ready"
    While Not FileExists($readyFile)
	    Sleep(3000)
    WEnd
EndFunc

Func setCloudflareFailed()
	Local $dirname = $sScriptDir
	; Specify the file path
	Local $filePath = $dirname & "" & $sPROJECT_NAME & "\.cloudflare.failed"

	; Open the file for writing (creates the file if it doesn't exist)
	Local $fileHandle = FileOpen($filePath, 2) ; 2 for write mode

	; Check if the file was opened successfully
	If $fileHandle = -1 Then
	    MsgBox(16, "Error", "Unable to open file for writing.")
	    Exit
	EndIf

	; Write the content to the file
	FileWrite($fileHandle, "ok")

	; Close the file handle
	FileClose($fileHandle)

	;MsgBox(64, "Success", "File written successfully.")

	; Exit the script
	;Exit
EndFunc

;~ ----------------------------------------------------------------

Func setDockerComposeYML($file)
	;ConsoleWrite($file)
	;$file = StringReplace($file, "\\", "/")
	;MsgBox($MB_SYSTEMMODAL, "Title " & FileExists($file), $file, 10)

	Local $template = FileRead($sProjectFolder & "\docker-build\image\docker-compose-template.yml")
	If FileExists($file) Then

	  Local $dirname = StringLeft($file, StringInStr($file, "\", 0, -1) - 1)
		If StringLeft($dirname, 1) = '"' Then
			$dirname = StringTrimLeft($dirname, 1)
		EndIf
	  
		Local $filename = StringMid($file, StringInStr($file, "\", 0, -1) + 1)


		$dirname = StringReplace($dirname, '\', "/")
		If StringRight($dirname, 1) = ':' Then
			$dirname = $dirname & "/"
		EndIf
			
		;MsgBox($MB_SYSTEMMODAL, "Title", $dirname, 10)

		
		;Local $template = FileRead($sProjectFolder & "\docker-build\image\docker-compose-template.yml")
		;ConsoleWrite($template)
		
		$template = StringReplace($template, "__SOURCE__", $dirname)
		$template = StringReplace($template, "__INPUT__", $filename)
	EndIf
	FileDelete($sProjectFolder & "\docker-compose.yml")
    FileWrite($sProjectFolder & "\docker-compose.yml", $template)
	;ConsoleWrite($template & @CRLF)
	
EndFunc

;~ ----------------------------------------------------------------

Func waitForConnection($port)
    Sleep(3000) ; Wait for 3 seconds
	Local $sURL = "http://127.0.0.1:" & $port

	Local $sFilePath = _WinAPI_GetTempFileName(@TempDir)

	While 1
		Local $iResult = InetGet($sURL, $sFilePath, $INET_FORCERELOAD)
		If $iResult <> -1 Then
			ConsoleWrite("Connection successful." & @CRLF)
			ExitLoop
		EndIf

		ConsoleWrite("Connection failed. Retrying in 5 seconds..." & @CRLF)
		Sleep(5000) ; Wait for 5 seconds before retrying
	WEnd
EndFunc

;~ ----------------------------------------------------------------

Func runDockerCompose()
	Local $dirname = StringLeft($sScriptDir, StringInStr($sScriptDir, "\", 0, -1) - 1)
	Local $cloudflareFile = $dirname & "\" & $sPROJECT_NAME & "\.cloudflare.url"
	If FileExists($cloudflareFile) Then
		FileDelete($cloudflareFile)
	EndIf
	
	RunWait(@ComSpec & " /c docker-compose down")
	If $PUBLIC_PORT = 0 then
		RunWait(@ComSpec & " /c docker-compose up --build")
		;Exit(0)
		Return
	Else
		RunWait(@ComSpec & " /c docker-compose up --build -d")
	EndIf

	waitForConnection($PUBLIC_PORT)
	
	;ConsoleWrite("getCloudflarePublicURL" & @CRLF)
	
	Local $cloudflare_url=getCloudflarePublicURL()

	waitForDockerAppReady()

	ConsoleWrite("================================================================" & @CRLF)
	ConsoleWrite("You can link the website via following URL:" & @CRLF)
	ConsoleWrite(@CRLF)

	If $cloudflare_url <> false Then
		ConsoleWrite($cloudflare_url)
	EndIf
	ConsoleWrite("http://127.0.0.1:" & $PUBLIC_PORT & @CRLF)
		

	ConsoleWrite(@CRLF)
	ConsoleWrite("Press Ctrl+C to stop the Docker container and exit." & @CRLF)
	ConsoleWrite("================================================================" & @CRLF)
	
	;Sleep(3000)
	;ShellExecute($cloudflare_url, "", "open", @SW_HIDE)
	
	
	If $cloudflare_url <> false Then
		ShellExecute($cloudflare_url)
		Sleep(3000)
	ElseIf $inited = 0 Then
		ShellExecute("http://127.0.0.1:" & $PUBLIC_PORT)
		Sleep(3000)
	EndIf
	
	; Display a message box with the OK button
	MsgBox(0, $sPROJECT_NAME, "Server is running. Click OK to exit the script.")
	
	RunWait(@ComSpec & " /c docker-compose down")

	; Exit the script
	;Exit(0)
	Return
EndFunc

;~ ---------------------

TrayTip("Docker APP", $sPROJECT_NAME & " is running", 60, 1)
If $INPUT_FILE = 1 Then 
	If $sUseParams = true Then
		For $i = 3 To $CmdLine[0]
			If Not FileExists($CmdLine[$i]) Then
				If Not FileExists($sWorkingDir & "/" & $CmdLine[$i]) Then
					MsgBox($MB_SYSTEMMODAL, $sPROJECT_NAME, "File not found: " & $CmdLine[$i])
				Else
					; ShellExecuteWait("node", $sProjectFolder & "\index.js" & ' "' & $sWorkingDir & "/" & $CmdLine[$i] & '"')	
					setDockerComposeYML('"' & $sWorkingDir & "/" & $CmdLine[$i] & '"')
					runDockerCompose()
				EndIf
			Else
				; ShellExecuteWait("node", $sProjectFolder & "\index.js" & ' "' & $CmdLine[$i] & '"')
				setDockerComposeYML($CmdLine[$i])
				runDockerCompose()
			EndIf
		Next
	Else
		For $i = 1 To $sFiles[0]
			;MsgBox($MB_SYSTEMMODAL, $sPROJECT_NAME, $sFiles[$i])
			If FileExists($sFiles[$i]) Then
				FileChangeDir($sProjectFolder)
				; ShellExecuteWait("node", $sProjectFolder & "\index.js" & ' "' & $sFiles[$i] & '"')
				setDockerComposeYML($sFiles[$i])
				runDockerCompose()
			EndIf
		Next
	EndIf
Else
	FileChangeDir($sProjectFolder)
	$ScriptFullPath = $CmdLine[2]
	setDockerComposeYML($ScriptFullPath)
	runDockerCompose()
EndIf

;~ ------------------------
; Process queue

While FileGetSize($lock_file_path) > 0
    ; Read the first line as the parameter
    Local $parameters = FileReadLine($lock_file_path)

    ; Remove the first line from the lock file
    Local $lines
	If _FileReadToArray($lock_file_path, $lines) Then
		_FileWriteFromArray($lock_file_path, $lines, 2)
	Else
		If FileExists($lock_file_path) Then
			FileDelete($lock_file_path)
		EndIf
	EndIf

    ; =================================================================
    If $parameters <> "" Then
        setDockerComposeYML('"' & $sWorkingDir & "/" & $parameters & '"')
				runDockerCompose()
    EndIf
WEnd

;~ ------------------------
; Remove lock

ConsoleWrite("Lock file is empty or does not exist. Removing and exiting..." & @CRLF)

If FileExists($lock_file_path) Then
    FileDelete($lock_file_path)
EndIf