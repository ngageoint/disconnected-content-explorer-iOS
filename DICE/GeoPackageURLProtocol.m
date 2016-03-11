//
//  GeoPackageURLProtocol.m
//  DICE
//
//  Created by Brian Osborn on 3/7/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageURLProtocol.h"
#import "GPKGGeoPackageFactory.h"
#import "GPKGGeoPackageCache.h"
#import "GPKGIOUtils.h"
#import "GPKGGeoPackageValidate.h"
#import "GPKGGeoPackageTileRetriever.h"
#import "URLProtocolUtils.h"
#import "GPKGFeatureTiles.h"
#import "ReportUtils.h"
#import "DICEConstants.h"

@interface GeoPackageURLProtocol () <NSURLConnectionDelegate>

@property (nonatomic, strong) NSString * path;
@property (nonatomic, strong) NSArray<NSString *> * tables;
@property (nonatomic) int zoom;
@property (nonatomic) int x;
@property (nonatomic) int y;
@property (nonatomic, strong) NSURLConnection *connection;

@end

@implementation GeoPackageURLProtocol

static NSString *urlProtocolHandledKey = @"GeoPackageURLProtocolHandledKey";
static GPKGGeoPackageManager * manager;
static GPKGGeoPackageCache *cache;
static NSString *currentId;

+ (void)start {
    manager = [GPKGGeoPackageFactory getManager];
    cache = [[GPKGGeoPackageCache alloc]initWithManager:manager];
    [NSURLProtocol registerClass:self];
}

+ (void) startCache: (NSString *) id{
    [self closeCache];
    currentId = id;
}

+ (void) closeCache{
    [cache closeAll];
    if(currentId != nil){
        NSString * like = [NSString stringWithFormat:@"%@%@", [self reportPrefix], @"%"];
        NSArray * geoPackages = [manager databasesLike:like];
        for(NSString * geoPackage in geoPackages){
            [manager delete:geoPackage andFile:NO];
        }
        currentId = nil;
    }
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    BOOL supports = NO;
    
    if(request != nil  && ![NSURLProtocol propertyForKey:urlProtocolHandledKey inRequest:request]){
        NSURL * url = [request URL];
        if(url != nil && [url isFileURL]){
            supports = [GPKGGeoPackageValidate hasGeoPackageExtension:url.path];
        }
    }
    
    return supports;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}


- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self != nil) {
        NSURL * url = [request URL];
        
        self.path = url.path;
        
        NSDictionary<NSString *, NSArray *> * query = [URLProtocolUtils parseQueryFromUrl:url];
        self.tables = [query valueForKey:@"table"];
        self.zoom = [[[query valueForKey:@"z"] objectAtIndex:0] intValue];
        self.x = [[[query valueForKey:@"x"] objectAtIndex:0] intValue];
        self.y = [[[query valueForKey:@"y"] objectAtIndex:0] intValue];

    }
    return self;
}

- (void)startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:urlProtocolHandledKey inRequest:newRequest];
    
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
    
    NSString * nameWithExtension = [self.path lastPathComponent];
    NSString * name = [nameWithExtension stringByDeletingPathExtension];
    
    NSString * localPath = [GPKGIOUtils localDocumentsDirectoryPath:self.path];
    NSString * sharedPrefix = [NSString stringWithFormat:@"%@/%@", currentId, DICE_REPORT_SHARED_DIRECTORY];
    BOOL shared = [localPath hasPrefix:sharedPrefix];
    if(!shared){
        NSString * reportIdPrefix = [GeoPackageURLProtocol reportIdPrefix];
        if(reportIdPrefix != nil){
            name = [NSString stringWithFormat:@"%@%@", reportIdPrefix, name];
        }else{
            name = nil;
        }
    }
    
    GPKGGeoPackage * geoPackage = nil;
    
    if(name != nil){
    
        if([manager exists:name]){
            @try {
                geoPackage = [cache getOrOpen:name];
            }
            @catch (NSException *exception) {
                [cache close:name];
                [manager delete:name andFile:NO];
                geoPackage = nil;
            }
        }
        
        if(geoPackage == nil){
            
            NSString * importPath = self.path;
            
            // If a shared file, check if the file exists in this report or another
            if(shared){
                NSFileManager * fileManager = [NSFileManager defaultManager];
                
                // If the file is not in this report, search other reports
                if(![fileManager fileExistsAtPath:importPath]){
                    
                    NSString * sharedSearchPath = [localPath substringFromIndex:[currentId length]];
                    
                    NSArray * reportDirectories = [ReportUtils getReportDirectories];
                    for(NSString * reportDirectory in reportDirectories){
                        
                        NSString * sharedLocation = [NSString stringWithFormat:@"%@%@", reportDirectory, sharedSearchPath];
                        
                        if([fileManager fileExistsAtPath:sharedLocation]){
                            importPath = sharedLocation;
                            break;
                        }
                    }

                }
            }
            
            [manager importGeoPackageAsLinkToPath:importPath withName:name];
            @try {
                geoPackage = [cache getOrOpen:name];
            }
            @catch (NSException *exception) {
                NSLog(@"Failed to open GeoPackage %@ at path: %@", name, importPath);
                geoPackage = nil;
            }
        }
    }
    
    NSData *tileData = nil;
    
    if(geoPackage != nil){
        for(NSString * table in self.tables){
            
            if([geoPackage isTileTable:table]){
            
                GPKGTileDao * tileDao = [geoPackage getTileDaoWithTableName:table];
            
                GPKGGeoPackageTileRetriever * retriever = [[GPKGGeoPackageTileRetriever alloc] initWithTileDao:tileDao];
                if([retriever hasTileWithX:self.x andY:self.y andZoom:self.zoom]){
                    GPKGGeoPackageTile * tile = [retriever getTileWithX:self.x andY:self.y andZoom:self.zoom];
                    if(tile != nil){
                        tileData = tile.data;
                    }
                }
            } else if([geoPackage isFeatureTable:table]){
                
                GPKGFeatureDao * featureDao = [geoPackage getFeatureDaoWithTableName:table];
                GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
                GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
                [featureTiles setIndexManager:indexer];
                if([featureTiles isIndexQuery] && [featureTiles queryIndexedFeaturesCountWithX:self.x andY:self.y andZoom:self.zoom] > 0){
                    tileData = [featureTiles drawTileDataWithX:self.x andY:self.y andZoom:self.zoom];
                }
            }
         
            if(tileData != nil){
                break;
            }
        }
    }
    
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:self.request.URL
                                                        MIMEType:nil
                                           expectedContentLength:tileData.length
                                                textEncodingName:nil];
    
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:tileData];
    [self.client URLProtocolDidFinishLoading:self];
    
}

- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
}

+(NSString *) reportPrefix{
    return DICE_TEMP_CACHE_PREFIX;
}

+(NSString *) reportIdPrefix{
    NSString * id = currentId;
    if(id != nil){
        id = [NSString stringWithFormat:@"%@%@-", [self reportPrefix], id];
    }
    return id;
}

@end
