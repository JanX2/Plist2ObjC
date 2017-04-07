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

NSString *generateIndent(NSUInteger level)
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

	return (idx > 0) ? [str substringFromIndex:idx] : str;
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
- (NSString *)recursiveDump:(NSUInteger)level;
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

- (NSString *)recursiveDump:(NSUInteger)level {
	return [NSString stringWithFormat:@"%@@\"%@\"",
	                 generateIndent(level),
	                 escape(self)
	       ];
}

@end

@implementation NSNumber (Plist2ObjC)

- (NSString *)recursiveDump:(NSUInteger)level {
	return [NSString stringWithFormat:@"%@@%@", generateIndent(level), self];
}

@end

@implementation NSArray (Plist2ObjC)

- (NSString *)recursiveDump:(NSUInteger)level {
	NSString *selfIndent = generateIndent(level);
	NSString *childIndent = [selfIndent stringByAppendingString:kIndentationString];
	NSMutableString *str = [NSMutableString stringWithString:@"@[\n"];

	for (NSUInteger i = 0; i < self.count; i++) {
		if (i > 0) {
			[str appendString:@",\n"];
		}

		[str appendFormat:@"%@%@",
		     childIndent,
		     removeIndentation([self[i] recursiveDump:level + 1])
		];
	}

	[str appendFormat:@"\n%@]", selfIndent];
	return str;
}

@end

@implementation NSDictionary (Plist2ObjC)

- (NSString *)recursiveDump:(NSUInteger)level {
	NSString *selfIndent = generateIndent(level);
	NSString *childIndent = [selfIndent stringByAppendingString:kIndentationString];
	NSMutableString *str = [NSMutableString stringWithString:@"@{\n"];
	
	__block NSUInteger i = 0;
	[self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		if (i > 0) {
			[str appendString:@",\n"];
		}
		
		[str appendFormat:@"%@%@: %@",
		 childIndent,
		 removeIndentation([key recursiveDump:level + 1]),
		 removeIndentation([obj recursiveDump:level + 1])
		 ];
		
		i += 1;
	}];
	
	[str appendFormat:@"\n%@}", selfIndent];
	return str;
}

@end

// feel free to implement handling NSData and NSDate here,
// it's not that straighforward as it is for basic data types, since
// - as far as I know - there's no literal initializer syntax for NSDate and NSData objects.

@implementation NSData (Plist2ObjC)

- (NSString *)recursiveDump:(NSUInteger)level {
	[NSException raise:NSInvalidArgumentException
	            format:@"Unimplemented - handling NSData is not yet supported"];
	return nil;
}

@end

@implementation NSDate (Plist2ObjC)

- (NSString *)recursiveDump:(NSUInteger)level {
	[NSException raise:NSInvalidArgumentException
	            format:@"Unimplemented - handling NSDate is not yet supported"];
	return nil;
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

void printUsage()
{
	printf("Usage: plist2objc <file.plist> [<file2.plist>]\n\n");
}

void dumpPlistRootedIn(id rootObj)
{
	NSString *code = [rootObj recursiveDump:0];
	printf("%s;\n", [code UTF8String]);
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		NSError *error;
		BOOL combineMultipleFiles = YES;
		
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
			
			id <Plist2ObjC_Dumpable, NSObject> obj =
			[NSPropertyListSerialization propertyListWithData:plistData
													  options:NSPropertyListImmutable
													   format:NULL
														error:&error];
			
			if (obj &&
				([obj isKindOfClass:[NSDictionary class]] ||
				 [obj isKindOfClass:[NSArray class]])
				) {
				
				if (!combineMultipleFiles || (pathCount == 1)) {
					rootObj = obj;
				}
				else {
					rootDict[plistFileKey] = obj;
				}
				
				if (!combineMultipleFiles) {
					printf("id %s = \n", [plistFileKey UTF8String]);
					dumpPlistRootedIn(rootObj);
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
			dumpPlistRootedIn(rootObj);
		}
		
		return EXIT_SUCCESS;
	}
}
