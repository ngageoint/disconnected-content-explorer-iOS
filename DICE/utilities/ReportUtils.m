//
//  ReportUtils.m
//  DICE
//
//  Created by Brian Osborn on 3/11/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "ReportUtils.h"
#import "GPKGIOUtils.h"

@implementation ReportUtils

+(NSArray *) getLocalReportDirectories{
    return [self getReportDirectoriesWithFullPath:NO];
}

+(NSArray *) getReportDirectories{
    return [self getReportDirectoriesWithFullPath:YES];
}

+(NSArray *) getReportDirectoriesWithFullPath: (BOOL) fullPath{

    NSFileManager * fileManager = [NSFileManager defaultManager];
    
    NSDirectoryEnumerator *documentsEnumerator = [fileManager enumeratorAtURL:[self documentsDirectoryUrl] includingPropertiesForKeys:[NSArray arrayWithObjects:NSURLNameKey, NSURLIsDirectoryKey,nil] options:NSDirectoryEnumerationSkipsSubdirectoryDescendants  errorHandler:nil];
    NSMutableArray *reportDirectories=[NSMutableArray array];
    
    for (NSURL *documentsUrl in documentsEnumerator) {
        
        NSString *fileName;
        [documentsUrl getResourceValue:&fileName forKey:NSURLNameKey error:NULL];
        
        NSNumber *isDirectory;
        [documentsUrl getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
        
        if([isDirectory boolValue] == YES && ![fileName isEqualToString:[GPKGIOUtils geoPackageDirectory]])
        {
            if(fullPath){
                 [reportDirectories addObject: [documentsUrl path]];
            }else{
                [reportDirectories addObject: fileName];
            }
        }
    }
    
    return reportDirectories;
}

+(NSString *) documentsDirectory{
    NSArray * paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString * documents = [paths objectAtIndex:0];
    return documents;
}

+(NSURL *) documentsDirectoryUrl{
    return [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
}

@end
