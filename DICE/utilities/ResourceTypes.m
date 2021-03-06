//
//  FileTypes.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/20/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <MobileCoreServices/UTType.h>

#import "ResourceTypes.h"


@interface ResourceTypes ()
@end


@implementation ResourceTypes

NSArray *supportedFileExtensions;
NSDictionary *resourceViewers;
UIStoryboard *activeStoryboard;

+ (void) initialize
{
    supportedFileExtensions = @[
        @"zip",
        @"pdf",
        @"doc",
        @"docx",
        @"ppt",
        @"pptx",
        @"xls",
        @"xlsx"
    ];
    
    resourceViewers = @{
        @"default": @"storyboard:htmlViewController",
        @"public.html": @"storyboard:htmlViewController",
        @"public.zip-archive": @"storyboard:htmlViewController",
        @"com.adobe.pdf": @"class:PDFViewController"
        // TODO: add office types
    };
    
    NSString *activeStoryboardName = [[NSBundle mainBundle].infoDictionary objectForKey:@"UIMainStoryboardFile"];
    activeStoryboard = [UIStoryboard storyboardWithName:activeStoryboardName bundle:nil];
}

+ (NSArray *)supportedFileExtensions
{
    return supportedFileExtensions;
}

+ (NSString *)typeUtiOf:(NSURL *)resource
{
    NSString *uti = nil;
    [resource getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:nil];
    if (!uti) {
        NSString *resourceExt = resource.pathExtension;
        CFStringRef utiRef = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)resourceExt, NULL);
        uti = (__bridge NSString *)utiRef;
        // TODO: does this do anything?
        [resource setResourceValue: uti forKey: NSURLTypeIdentifierKey error: nil];
    }
    return uti;
}

+ (BOOL)canOpenResource:(NSURL *)resource
{
    NSString *uti = [ResourceTypes typeUtiOf:resource];
    if ([resourceViewers valueForKey:uti]) {
        return YES;
    }
    NSArray *docTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
    docTypes = [docTypes filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *docType, NSDictionary *bindings) {
        NSArray *utiList = [docType objectForKey:@"LSItemContentTypes"];
        return [utiList containsObject:uti];
    }]];
    return docTypes.count > 0 || [supportedFileExtensions containsObject:resource.pathExtension.lowercaseString];
}

+ (UIViewController<ResourceHandler> *)viewerForResource:(NSURL *)resource
{
    NSString *uti = [self typeUtiOf:resource];
    NSString* viewerSpec = resourceViewers[uti];
    
    if (!viewerSpec) {
        if ([supportedFileExtensions containsObject:resource.pathExtension.lowercaseString]) {
            viewerSpec = resourceViewers[@"default"];
        }
        else {
            return nil;
        }
    }
    
    NSArray *viewerParts = [viewerSpec componentsSeparatedByString:@":"];
    NSString *viewerType = viewerParts[0];
    NSString *viewerID = viewerParts[1];
    UIViewController<ResourceHandler> *viewController = nil;
    
    if ([viewerType isEqualToString:@"class"]) {
        Class viewerClass = NSClassFromString(viewerID);
        viewController = [[viewerClass alloc] init];
    }
    else if ([viewerType isEqualToString:@"storyboard"]) {
        viewController = [activeStoryboard instantiateViewControllerWithIdentifier:viewerID];
    }
    
    return viewController;
}

@end
