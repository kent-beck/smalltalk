"======================================================================
|
|   Smalltalk package installer
|
|
 ======================================================================"


"======================================================================
|
| Copyright 2007 Free Software Foundation, Inc.
| Written by Paolo Bonzini.
|
| This file is part of GNU Smalltalk.
|
| GNU Smalltalk is free software; you can redistribute it and/or modify it
| under the terms of the GNU General Public License as published by the Free
| Software Foundation; either version 2, or (at your option) any later version.
|
| GNU Smalltalk is distributed in the hope that it will be useful, but WITHOUT
| ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
| FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
| details.
|
| You should have received a copy of the GNU General Public License along with
| GNU Smalltalk; see the file COPYING.  If not, write to the Free Software
| Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
|
 ======================================================================"


Package extend [
    srcdir [
	^self baseDirectories last
    ]

    isStarPackageBody [
	^'*.star#uzip' match: self baseDirectories first
    ]

    starFileName [
	| dir |
	self isStarPackageBody ifFalse: [ self halt ].
	dir := self baseDirectories first.
	^dir copyFrom: 1 to: dir size - 5 ]

    runCommand: aCommand [
	self isStarPackageBody
	    ifTrue: [ aCommand runOnStar: self ]
	    ifFalse: [ aCommand runOnPackage: self ]
    ]
]

Kernel.PackageDirectory subclass: StarPackageFile [
    refreshStarList: dir [
	| package |
	package := Kernel.StarPackage fileName: self fileName.
        packages at: package name put: package loadedPackage
    ]

    refreshPackageList []
]

Kernel.PackageDirectory subclass: PackageFile [
    refreshStarList: dir []

    refreshPackageList [
        | file |
	file := FileStream open: fileName mode: FileStream read.
	[ self parse: file ]
	    ensure: [ file close ].
    ]
]

Kernel.PackageDirectories subclass: PackageFiles [
    | srcdir |

    addAllFiles: aCollection [
	aCollection do: [ :each | self addFile: each ]
    ]

    addFile: fileName [
	| packageFile |
	packageFile := ('*.star' match: fileName)
	    ifFalse: [
		PackageFile
		    on: fileName
		    baseDirectories: [ self baseDirsFor: fileName ] ]
	    ifTrue: [
		StarPackageFile
		    on: fileName
		    baseDirectories: [ fileName, '#uzip' ] ].

	packageFile refresh.
	self add: packageFile.
    ]

    baseDirsFor: fileName [
	| file srcdirPath builddirPrefix |
	file := File name: fileName.
	self srcdir isNil ifTrue: [ ^{ file path } ].

	"See if the file is in srcdir or builddir.  In any case, we want to
	 look for files first in the builddir, and secondarily in srcdir."
	srcdirPath := file pathFrom: srcdir.
	builddirPrefix := (Directory name: Directory working) pathFrom: srcdir.
	^(srcdirPath startsWith: builddirPrefix, Directory pathSeparatorString)
	    ifFalse: [
		"file is in srcdir."
		{ File pathFor: srcdirPath. file path } ]
	    ifTrue: [ {
		"file is in builddir."
		file path.
		Directory append: (File pathFor: fileName) to: self srcdir } ]
    ]

    filesDo: aBlock [
	(dirs collect: [ :each | each fileName ]) asSet do: aBlock
    ]

    srcdir [
	^srcdir
    ]

    srcdir: aString [
	srcdir := aString
    ]
]

File extend [
    emitZipDir: dir [
	| saveDir |
	self emitRemove.
	('cd %1 && %2 -qr %3 .' % { dir. Command zip. self }) displayNl.
        saveDir := Directory working.
	Command
	    execute: [
	        Directory working: dir name.
		Smalltalk system: '%1 -qr %2 .' % { Command zip. self }
	    ]
	    ensure: [ Directory working: saveDir ]
    ]

    emitRemove [
	('rm -f %1' % { self }) displayNl.
	Command execute: [
	    self exists ifTrue: [ self remove ] ].
    ]

    emitSymlink: dest [
	| destFile |
	('%1 -f %2 %3' % { Command symLink. self. dest }) displayNl.
	Command execute: [
	    destFile := File name: dest.
	    destFile exists ifTrue: [ destFile remove ].
	    self symlinkAs: dest ].
    ]

    emitInstall: dest [
	| destFile srcStream destStream mode |
	mode := self isExecutable ifTrue: [ 8r755 ] ifFalse: [ 8r644 ].
	destFile := File name: dest.
	('%1 -m %2 %3 %4' % {
	    Command install. self. mode printString: 8. destFile })
		displayNl.
	Command
	    execute: [
	        destFile exists ifTrue: [ destFile remove ].
	        srcStream := self readStream.
		destStream := destFile writeStream.
	        destStream nextPutAll: srcStream.
	    ]
	    ensure: [
		destStream isNil ifFalse: [ destStream close ].
		srcStream isNil ifFalse: [ srcStream close ].
		destFile mode: mode
	    ].
    ]
]

Directory extend [
    emitMkdir [
	| doThat |
	self exists ifTrue: [ ^self ].
	Command execute: [ self directory emitMkdir ].
	('mkdir %1' % { self }) displayNl.
	Command execute: [ Directory create: self name ].
    ]
]

Object subclass: Command [
    | packages installDir options |

    DryRun := false.
    Command class >> execute: aBlock [
	DryRun ifFalse: [ aBlock value ]
    ]
    Command class >> execute: aBlock ensure: ensureBlock [
	DryRun ifFalse: [ aBlock ensure: ensureBlock ]
    ]
    Command class >> dryRun [
	^DryRun
    ]
    Command class >> dryRun: aBoolean [
	DryRun := aBoolean
    ]

    Command class >> zip [
	^(Smalltalk getenv: 'XZIP') ifNil: [ 'zip' ]
    ]
    Command class >> install [
	^(Smalltalk getenv: 'INSTALL') ifNil: [ 'install' ]
    ]
    Command class >> symLink [
	^(Smalltalk getenv: 'LN_S') ifNil: [ 'ln -s' ]
    ]

    options: aSet [
	options := aSet.
	aSet do: [ :each |
	    (self validOptions includes: each) ifFalse: [
		self error: ('option %1 invalid for this mode' % {each}) ] ]
    ]
    validOptions [ ^#() ]
    isOption: aString [ ^options includes: aString ]

    validateDestDir: destdir installDir: instDir [ 
	instDir isNil ifTrue: [ ^self ].
	((Directory name: instDir) name ~= instDir
	    and: [ destdir notEmpty ]) ifTrue: [
		self error: '--destdir used with relative target directory' ]
    ]

    destDir: destdir installDir: instDir [
	self validateDestDir: destdir installDir: instDir.
	installDir :=
	    Directory name:
	        destdir, (instDir ifNil: [ self defaultInstallDir ])
    ]

    defaultInstallDir [ ^Directory image ]
    installDir [ ^installDir ]

    packages [
	packages isNil ifTrue: [ packages := PackageFiles new ].
	^packages 
    ]

    srcdir [
	^self packages srcdir ifNil: [ '.' ]
    ]
    srcdir: aString [
	(aString = '.' or: [ (File fullNameFor: aString) = Directory working ])
	    ifTrue: [ self packages srcdir: nil ]
	    ifFalse: [ self packages srcdir: aString ]
    ]

    addAllFiles: aCollection [ self packages addAllFiles: aCollection ]

    prolog [ ]
    run [ self packages do: [ :pkg | pkg runCommand: self ] ]
    runOnStar: aStarPackage [ self runOnPackage: aStarPackage ]
    runOnPackage: aPackage [ ]

    listFiles: listFiles [
	| base vpathBase vpath |
	vpath := self isOption: 'vpath'.
	base := self installDir.
	vpathBase := Directory name: self srcdir.

        listFiles do: [ :each || package |
	    package := self packages at: each.
	    package allFiles do: [ :file |
		| path relativePath |
		path := package findPathFor: file.
		relativePath := base pathTo: path.
		(vpath and: [ (relativePath indexOfSubCollection: '../') > 0 ])
		    ifTrue: [ relativePath := vpathBase pathTo: path ].

		relativePath displayNl ] ]
    ]
]

Command subclass: PkgDist [
    validateDestDir: destdir installDir: instDir [ 
	(destdir isEmpty and: [ instDir isNil ]) ifTrue: [
	    self error: 'using --dist without specifying --distdir' ].
    ]

    defaultInstallDir [ ^'' ]
    run [
	super run.

	"Distribute package files, unless they are automatically generated
	 from autoconf."
	packages filesDo: [ :each |
	    | destName autoconfName srcdir |
	    destName := File stripPathFrom: each.
	    srcdir := Directory append: (File pathFor: each) to: self srcdir.
	    autoconfName := destName, '.in'.
	    ((Directory name: srcdir) includes: autoconfName)
		ifFalse: [
		    self distribute: (File name: each)
			as: destName
			in: nil ] ]
    ]

    validOptions [ ^#('all-files' 'copy') ]

    distribute: srcFile as: file in: dir [
	| destName baseDir |
	baseDir := self installDir.
	dir isNil ifFalse: [ baseDir := baseDir directoryAt: dir ].
	destName := baseDir nameAt: file.
	(self isOption: 'copy')
	    ifTrue: [ srcFile emitInstall: destName ]
	    ifFalse: [ srcFile emitSymlink: destName ]
    ]

    runOnPackage: aPackage [
	| dirs files baseDir |
	files := (self isOption: 'all-files')
	    ifTrue: [ aPackage allFiles ]
	    ifFalse: [ aPackage allDistFiles ].

        dirs := files collect: [ :file | File pathFor: file ].
	dirs := dirs asSet asOrderedCollection.

	aPackage relativeDirectory isNil ifFalse: [
	    dirs := dirs collect: [ :dir |
		Directory append: dir to: aPackage relativeDirectory ] ].

        dirs do: [ :dir || destName |
	    (self installDir directoryAt: dir) emitMkdir ].

        files do: [ :file || srcFile destName |
	    srcFile := File name: (aPackage findPathFor: file).
	    self distribute: srcFile as: file in: aPackage relativeDirectory ]
    ]
    runOnStar: aPackage [
	self error: 'cannot distribute sources from .star file'
    ]
]

Command subclass: PkgInstall [
    | tmpDir |
    validOptions [ ^#('load' 'test') ]

    run [
        "Create the installation directory."
        self installDir emitMkdir.
	[ super run ] ensure: [
	    tmpDir isNil ifFalse: [ tmpDir remove ] ].

	(Command dryRun not and: [ self isOption: 'load' ])
	    ifTrue: [ ^self loadPackages ].

	(self isOption: 'test') ifTrue: [ self runTests ]
    ]

    runTests [
	"Run SUnit tests, used unless --load is given too."
	| script result |
	script := ''.
	self packages do: [ :each || pkg |
	    pkg := each.
            script := script, ' ', pkg sunitScript.
            pkg test notNil ifTrue: [
                pkg := pkg test.
                script := script, ' ', pkg sunitScript ].
            pkg fileIn ].

	(PackageLoader packageAt: #SUnit) loaded ifFalse: [ ^self ].
	script isEmpty ifTrue: [ ^self ].

	result := TestSuitesScripter run: script quiet: false verbose: false.
	result runCount = result passedCount
	    ifFalse: [ ObjectMemory quit: 1 ]
    ]

    loadPackages [
	"Call gst-load, needed because we added our code to the image."
	| gstPackage execDir gstLoad pat packageList |
	gstPackage := File name: File executable.
	gstPackage stripPath = 'gst-tool'
	    ifTrue: [
		gstLoad := gstPackage.
		pat := '%1 gst-load -I %2 --kernel-directory %3 %4 %5' ]
	    ifFalse: [
		gstLoad := gstPackage directory fileAt: 'gst-load'.
		pat := '%1 -I %2 --kernel-directory %3 %4 %5' ].

	packageList := ''.
	self packages
	    do: [ :each | packageList := packageList, ' ', each name ].

	Smalltalk system: (pat % {
	    gstLoad.
	    File name: File image.
	    Directory name: Directory kernel.
	    (self isOption: 'test') ifTrue: [ '--test' ] ifFalse: [ '' ].
	    packageList })
    ]

    tmpDir [
	tmpDir isNil ifTrue: [
            tmpDir := Directory createTemporary: Directory temporary, '/gstar-'.
            ('mkdir %1' % { tmpDir }) displayNl ].
	^tmpDir
    ]

    runOnPackage: aPackage [
	| pkg destFile dirs files baseDir |
	baseDir := self tmpDir directoryAt: aPackage name.
	pkg := aPackage copy.
	pkg relativeDirectory: nil.

	baseDir emitMkdir.
	Command
	    execute: [
	        (baseDir fileAt: 'package.xml') withWriteStreamDo: [ :s |
	            pkg printOn: s ].

	        files := pkg allFiles.
                dirs := files collect: [ :file | File pathFor: file ].
	        dirs asSet asSortedCollection do: [ :dir |
	            (baseDir directoryAt: dir) emitMkdir ].

                files do: [ :file || srcFile |
	            srcFile := File name: (aPackage findPathFor: file).
	            srcFile emitSymlink: (baseDir nameAt: file) ].

	        (self installDir fileAt: aPackage name, '.star')
		    emitZipDir: baseDir
	    ]
	    ensure: [
	        "Clean up our mess."
	        (baseDir fileAt: 'package.xml') remove.
                files do: [ :file |
	            (baseDir fileAt: file) remove ].
	        dirs asSet asSortedCollection do: [ :dir |
	            (baseDir directoryAt: dir) remove ]
	    ].
    ]

    runOnStar: aPackage [
	| destFile |
	destFile := self installDir nameAt: aPackage name, '.star'.
	(File name: aPackage starFileName) emitInstall: destFile.
    ]
]

Command subclass: PkgUninstall [
    run [
        super run.
        packages filesDo: [ :each | (File name: each) emitRemove ]
    ]

    runOnPackage: aPackage [
	| baseDir |
	baseDir := self installDir.
	aPackage relativeDirectory isNil ifFalse: [
	    baseDir := baseDir directoryAt: aPackage relativeDirectory ].

	aPackage allFiles do: [ :file |
	    (baseDir fileAt: file) emitRemove ]
    ]

    runOnStar: aPackage [ ]
]

Command subclass: PkgList [
    validOptions [ ^#('list-files' 'vpath') ]
    validateDestDir: destdir installDir: installDir [ ]
]

PkgList subclass: PkgPackageList [
    runOnPackage: aPackage [ aPackage name displayNl ]
]

| srcdir installDir mode listFiles destdir packageFiles helpString options |

mode := nil.
listFiles := OrderedCollection new.
installDir := nil.
destdir := ''.
srcdir := '.'.
options := Set new.
packageFiles := OrderedCollection new.
packages := PackageFiles new.

helpString := 
'Usage:
    gst-package [OPTION]... FILES...

Operation modes:
        --install               make or install STAR packages (default)
        --uninstall             remove the packages mentioned in the FILES
        --dist                  copy files instead of creating STAR files.
        --list-files PKG        just output the list of files in the package
        --list-packages         just output the list of packages in the files
	--help                  display this message and exit
	--version               print version information and exit

Common suboptions:
    -n, --dry-run               print commands without running them
	--srcdir DIR            look for non-built files in directory DIR
	--distdir DIR	        for --dist, place files in directory DIR
	--destdir DIR	        prefix the destination directory with DIR
        --target-directory DIR  install the files in DIR (unused for --dist)
    -I, --image-file=FILE       load into the specified image
        --kernel-dir=PATH       use the specified kernel directory

--install suboptions:
	--test                  run unit tests after merging
	--load                  also load the Smalltalk files in the image

--list-files suboptions:
	--vpath			Omit path to srcdir for files that are there

--dist suboptions:
        --all-files             Process all files, not just non-built ones
        --copy                  Do not create symbolic links

Except in uninstall and list files mode, gst-package requires write
access to the GNU Smalltalk image directory, and merges the XML package
files on the command line with that file.

The default target directory is ', Directory image, '
'.

[
    Smalltalk
        "--kenrel-directory and --image-file are processed by gst-tool.
	 --no-load present for backwards compatibility, it is now the default.
	 --no-install is also present for backwards compatibility."
        arguments: '-h|--help --no-load --test --load --no-install --uninstall
            --dist -t|--target-directory: --list-files: --list-packages
            --srcdir: --distdir|--destdir: -n|--dry-run --all-files
	    --vpath --copy -I|--image-file: --kernel-directory:'

        do: [ :opt :arg |
            opt = 'help' ifTrue: [
                helpString displayOn: stderr.
                ObjectMemory quit: 0 ].

            opt = 'uninstall' ifTrue: [
		mode isNil ifFalse: [ self error: 'multiple modes specified' ].
		mode := PkgUninstall ].
            opt = 'dist' ifTrue: [
		mode isNil ifFalse: [ self error: 'multiple modes specified' ].
		mode := PkgDist ].
            opt = 'list-packages' ifTrue: [
		mode isNil ifFalse: [ self error: 'multiple modes specified' ].
		mode := PkgPackageList ].
            opt = 'no-install' ifTrue: [
		mode isNil ifFalse: [ self error: 'multiple modes specified' ].
		mode := PkgList ].
            opt = 'list-files' ifTrue: [
		mode isNil ifFalse: [ self error: 'multiple modes specified' ].
		listFiles add: arg.
		mode := PkgList ].

            opt = 'target-directory' ifTrue: [ installDir := arg ].

            opt = 'srcdir' ifTrue: [ srcdir := arg ].
            opt = 'destdir' ifTrue: [ destdir := arg ].
            opt = 'dry-run' ifTrue: [ Command dryRun: true ].
            opt = 'test' ifTrue: [ options add: opt ].
            opt = 'load' ifTrue: [ options add: opt ].
            opt = 'all-files' ifTrue: [ options add: opt ].
            opt = 'copy' ifTrue: [ options add: opt ].
            opt = 'vpath' ifTrue: [ options add: opt ].

            opt isNil ifTrue: [ packageFiles add: arg ] ]
        ifError: [
            helpString displayOn: stderr.
            ObjectMemory quit: 1 ].

    mode isNil ifTrue: [ mode := PkgInstall ].

    "Validate the installation and source directory."
    mode new
        destDir: destdir installDir: installDir;
	srcdir: srcdir;
	addAllFiles: packageFiles;
	options: options;
	prolog;
	run;
	listFiles: listFiles
]
    on: Error
    do: [ :ex |
	('gst-package: ', ex messageText, '
') displayOn: stderr.
	"ex pass." ObjectMemory quit: 1 ].