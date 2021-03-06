TestCase subclass: WACodecTest [
    
    <comment: nil>
    <category: 'Seaside-Adapters-Tests'>

    testGeneric [
	<category: 'testing'>
	#('utf-8' 'iso-8859-1') do: [:each | self assert: each notNil]
    ]

    testLatin1Codec [
	<category: 'testing'>
	| codec |
	codec := WACodec forEncoding: 'ISO-8859-1'.
	self assert: codec notNil.
	self assert: (codec encode: '�b�rstr��g�') = '�b�rstr��g�'.
	self assert: (codec decode: '�b�rstr��g�') = '�b�rstr��g�'.
	self assert: (codec decodeUrl: '�b�rstr��g�') = '�b�rstr��g�'
    ]

    testNullCodec [
	<category: 'testing'>
	| codec |
	codec := WACodec forEncoding: nil.
	self assert: codec notNil.
	self assert: codec class = WANullCodec.
	self assert: (codec encode: '�b�rstr��g�') = '�b�rstr��g�'.
	self assert: (codec decode: '�b�rstr��g�') = '�b�rstr��g�'.
	self assert: (codec decodeUrl: '�b�rstr��g�') = '�b�rstr��g�'
    ]

    testUtf8Codec [
	<category: 'testing'>
	| codec |
	codec := WACodec forEncoding: 'UTF-8'.
	self assert: codec notNil.
	self assert: (codec encode: '�b�rstr��g�') = 'Übèrstrîñgé'.
	self assert: (codec decode: 'Übèrstrîñgé') = '�b�rstr��g�'.
	self assert: (codec decodeUrl: 'Übèrstrîñgé') = '�b�rstr��g�'
    ]
]

