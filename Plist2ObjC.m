/*
 * Plist2ObjC.m
 * Plist2ObjC
 *
 * Created by Arpad Goretity on 24/10/2012
 * Licensed under the 3-clause BSD License
 */

#import <stdio.h>
#import <Foundation/Foundation.h>

static NSString * const kIndentationString = @"\t";

static NSString * const kFileNameKey = @"Plist2ObjCFileName";
static NSString * const kFilePathKey = @"Plist2ObjCFilePath";
static NSString * const kFileDateKey = @"Plist2ObjCFileModificationDate";


typedef NS_OPTIONS(NSUInteger, PlistDumpOptions) {
	PlistDumpUseSpaceForIndentation			   = 1 << 0,
};

NSString *indentationStringForLevel(NSUInteger level)
{
	return [@"" stringByPaddingToLength:level
							 withString:kIndentationString
						startingAtIndex:0];
}

NSString *removeIndentation(NSString *str)
{
	const NSUInteger len = str.length;
	NSUInteger idx = 0;
	
	for (NSUInteger i = 0; i < len; i++) {
		unichar c = [str characterAtIndex:i];
		if (c != '\t') {
			idx = i;
			break;
		}
	}
	
	NSString *result =
	(idx > 0) ? [str substringFromIndex:idx] : str;
	
	return result;
}

NSString *escape(NSString *str)
{
	static NSDictionary *replacements;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		replacements = @{
						 @"\"": @"\\\"",
						 @"\\": @"\\\\",
						 @"\'": @"\\\'",
						 @"\n": @"\\n",
						 @"\r": @"\\r",
						 @"\t": @"\\t"
						 };
	});

	for (NSString *key in replacements) {
		str = [str stringByReplacingOccurrencesOfString:key withString:replacements[key]];
	}

	return str;
}

@protocol Plist2ObjC_Dumpable
- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options;
@end

@interface NSString (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@interface NSNumber (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@interface NSArray (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@interface NSDictionary (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@interface NSData (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@interface NSDate (Plist2ObjC) <Plist2ObjC_Dumpable>
@end

@implementation NSString (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	return [NSString stringWithFormat:@"%@@\"%@\"",
					 indentationStringForLevel(level),
					 escape(self)
		   ];
}

@end

@implementation NSNumber (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	return [NSString stringWithFormat:@"%@@%@", indentationStringForLevel(level), self];
}

@end

@implementation NSArray (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	NSString *selfIndent = indentationStringForLevel(level);
	NSString *childIndent = [selfIndent stringByAppendingString:kIndentationString];
	NSMutableString *str = [NSMutableString stringWithString:@"@[\n"];

	for (NSUInteger i = 0; i < self.count; i++) {
		if (i > 0) {
			[str appendString:@",\n"];
		}

		[str appendFormat:@"%@%@",
			 childIndent,
			 removeIndentation([self[i] recursiveDumpWithLevel:(level + 1)
										   			   options:options])
		 ];
	}

	[str appendFormat:@"\n%@]", selfIndent];
	return str;
}

@end

@implementation NSDictionary (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	NSString *selfIndent = indentationStringForLevel(level);
	NSString *childIndent = [selfIndent stringByAppendingString:kIndentationString];
	NSMutableString *str = [NSMutableString stringWithString:@"@{\n"];
	
	__block NSUInteger i = 0;
	[self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		if (i > 0) {
			[str appendString:@",\n"];
		}
		
		[str appendFormat:@"%@%@: %@",
		 childIndent,
		 removeIndentation([key recursiveDumpWithLevel:level + 1
											   options:options]),
		 removeIndentation([obj recursiveDumpWithLevel:level + 1
											   options:options])
		 ];
		
		i += 1;
	}];
	
	[str appendFormat:@"\n%@}", selfIndent];
	return str;
}

@end

// Implementation for NSData and NSDate based on
// https://github.com/fourplusone/plist2code

@implementation NSData (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	NSUInteger length = self.length;
	const char *bytes = self.bytes;
	NSMutableString *str = [[NSMutableString alloc] initWithString:@"[NSData dataWithBytes:\""];
	
	for (NSUInteger i = 0; i < length; i++) {
		char c = bytes[i];
		[str appendFormat:@"\\x%02x", c & 0xff];
	}
	
	[str appendFormat:@"\" length:%ld]", length];
	
	return str;
}

@end

@implementation NSDate (Plist2ObjC)

- (NSString *)recursiveDumpWithLevel:(NSUInteger)level
							 options:(PlistDumpOptions)options {
	NSTimeInterval interval = [self timeIntervalSince1970];
	return [NSString stringWithFormat:@"[NSDate dateWithTimeIntervalSince1970:%f]", interval];
}

@end


// Determine a unique key for each plist.
NSMutableArray * determineFileKeys(NSArray *plistFilePaths) {
	NSUInteger pathCount = plistFilePaths.count;
	
	NSMutableArray *fileKeys = [NSMutableArray arrayWithCapacity:pathCount];
	
	NSUInteger componentOffset = NSNotFound;
	
	NSUInteger minComponentCount = NSNotFound;
	NSMutableArray <NSArray *> *plistFilesPathComponents = [NSMutableArray arrayWithCapacity:pathCount];
	for (NSString *plistFilePath in plistFilePaths) {
		NSArray<NSString *> *pathComponents = [plistFilePath pathComponents];
		[plistFilesPathComponents addObject:pathComponents];
		
		if (minComponentCount == NSNotFound) {
			minComponentCount = pathComponents.count;
		}
		else {
			minComponentCount = MIN(minComponentCount, pathComponents.count);
		}
	}
	
	// Find the smallest path component offset from the end, where there are no duplicates.
	NSMutableSet *keySet = [NSMutableSet set];
	for (NSUInteger offset = 0; offset < minComponentCount; offset += 1) {
		BOOL foundDupe = NO;
		for (NSArray<NSString *> *pathComponents in plistFilesPathComponents) {
			NSString *componentAtOffset = pathComponents[pathComponents.count-1 - offset];
			if ([keySet containsObject:componentAtOffset]) {
				foundDupe = YES;
				break;
			}
			else {
				[keySet addObject:componentAtOffset];
				NSString *key = componentAtOffset;
				if (offset == 0) {
					key = [componentAtOffset stringByDeletingPathExtension];
				}
				[fileKeys addObject:key];
			}
		}
		
		if (foundDupe) {
			[keySet removeAllObjects];
			[fileKeys removeAllObjects];
		}
		else {
			componentOffset = offset;
			break;
		}
		
	}
	
	if (componentOffset == NSNotFound) {
		printf("Error: Could not determine a unique key for each plist.\n");
		exit(EXIT_FAILURE);
	}
	
	return fileKeys;
}

NSString * dateStringForFilePath(NSString *filePath) {
	NSError *error;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:filePath
																 error:&error];
	if (fileAttributes == nil)  NSLog(@"Error while fetching attributes: %@", error);
	NSDate *fileDate = [fileAttributes objectForKey:NSFileModificationDate];
	NSString *fileDateString = [fileDate descriptionWithLocale:nil];
	
	return fileDateString;
}

void insertFileMetadataIntoDictionaryRoot(id obj, NSDictionary *fileMetadata) {
	NSMutableDictionary *rootDictionary = (NSMutableDictionary *)obj;
	[rootDictionary addEntriesFromDictionary:fileMetadata];
}

void printUsage()
{
	printf("Usage: plist2objc <file.plist> [<file2.plist>]\n\n");
}

void dumpPlistRootedIn(id rootObj, PlistDumpOptions options)
{
	NSString *code = [rootObj recursiveDumpWithLevel:0
											 options:options];
	printf("%s;\n", [code UTF8String]);
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		NSError *error;
		BOOL combineMultipleFiles = YES;
		BOOL addFileMetadataToDictionaryRoot = NO;
		
		PlistDumpOptions dumpOptions = PlistDumpUseSpaceForIndentation;
		
		NSArray *processArguments = [[NSProcessInfo processInfo] arguments];
		NSUInteger argumentCount = processArguments.count;
		
		if (argumentCount < 2) {
			printUsage();
			printf("Error: Invalid arguments supplied.\n");
			return EXIT_FAILURE;
		}
		
		const NSUInteger firstPathArgumentIndex = 1;
		
		NSUInteger pathCount = argumentCount - firstPathArgumentIndex;
		NSArray *plistFilePaths = [processArguments subarrayWithRange:NSMakeRange(firstPathArgumentIndex, pathCount)];
		
		id <Plist2ObjC_Dumpable, NSObject> rootObj;
		NSMutableDictionary *rootDict = nil;
		NSMutableArray *fileKeys = nil;
		
		// Multiple plist files will be combined into a single data structure (`combineMultipleFiles`)
		// or emitted as separate variables.
		// We need unique names in both cases.
		if (pathCount > 1) {
			rootDict = [NSMutableDictionary dictionaryWithCapacity:pathCount];
			rootObj = rootDict;
			
			fileKeys = determineFileKeys(plistFilePaths);
			
			if (!combineMultipleFiles) {
				// TODO: Convert `fileKeys` into valid, unique C variable names.
			}
		}
		
		NSUInteger i = 0;
		for (NSString *plistFilePath in plistFilePaths) {
			NSString *plistFileName = [plistFilePath lastPathComponent];
			NSString *plistFileKey = fileKeys ? fileKeys[i] : [plistFileName stringByDeletingPathExtension];
			NSData *plistData = [NSData dataWithContentsOfFile:plistFilePath];
			
			NSPropertyListReadOptions options =
			addFileMetadataToDictionaryRoot ? NSPropertyListMutableContainers : NSPropertyListImmutable;
			
			id <Plist2ObjC_Dumpable, NSObject> obj =
			[NSPropertyListSerialization propertyListWithData:plistData
													  options:options
													   format:NULL
														error:&error];
			
			BOOL rootIsDictionary = NO;
			BOOL rootIsArray = NO;
			
			if (obj &&
				((rootIsDictionary = [obj isKindOfClass:[NSDictionary class]]) ||
				 (rootIsArray = [obj isKindOfClass:[NSArray class]]))
				) {
				
				if (rootIsDictionary &&
					addFileMetadataToDictionaryRoot) {
					insertFileMetadataIntoDictionaryRoot(obj,
														 @{
														   kFileNameKey: plistFileName,
														   kFilePathKey: plistFilePath,
														   kFileDateKey: dateStringForFilePath(plistFilePath),
														   }
														 );
				}
				
				if (!combineMultipleFiles || (pathCount == 1)) {
					rootObj = obj;
				}
				else {
					rootDict[plistFileKey] = obj;
				}
				
				if (!combineMultipleFiles) {
					printf("id %s = \n", [plistFileKey UTF8String]);
					dumpPlistRootedIn(rootObj, dumpOptions);
					printf("\n\n");
				}
			}
			else {
				// Must be an invalid file.
				if (!obj) {
					printf("%s\n", [[error description] UTF8String]);
				}
				
				printUsage();
				printf("Error: Invalid file supplied.\n");
				return EXIT_FAILURE;
			}
			
			i += 1;
		}
		
		if (combineMultipleFiles) {
			printf("id plistRoot = \n");
			dumpPlistRootedIn(rootObj, dumpOptions);
		}
		
		return EXIT_SUCCESS;
	}
}
