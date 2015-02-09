//
//  OfflineMapUtility.h
//
//

#import <Foundation/Foundation.h>

#import <MapKit/MapKit.h>

@interface OfflineMapUtility : NSObject

+ (NSArray*)getPolygons;
+ (NSDictionary*)dictionaryWithContentsOfJSONString:(NSString*)fileLocation;
+ (void) generateExteriorPolygons:(NSMutableArray*) featuresArray;
+ (MKPolygon *) generatePolygon:(NSMutableArray *) coordinates;

@end
