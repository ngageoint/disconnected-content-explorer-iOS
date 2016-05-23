//
//  ZippedHtmlImportProcess.h
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ImportProcess+Internal.h"
#import "UnzipOperation.h"
#import "ZipFile.h"



typedef NS_ENUM(NSUInteger, ZippedHtmlImportStep) {
    ZippedHtmlImportValidateStep = 0,
    ZippedHtmlImportMakeBaseDirStep = 1,
    ZippedHtmlImportUnzipStep = 2,
    ZippedHtmlImportParseDescriptorStep = 3,
    ZippedHtmlImportDeleteStep = 4
};



@interface ZippedHtmlImportProcess : ImportProcess <UnzipDelegate>

@property (readonly) NSURL *destDir;

- (instancetype)initWithReport:(Report *)report
                       destDir:(NSURL *)destDir
                       zipFile:(ZipFile *)zipFile
                   fileManager:(NSFileManager *)fileManager;

@end