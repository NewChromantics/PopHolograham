Shader "NewChromantics/RayVolume"
{
	Properties
	{
		_MainTex ("Base (RGB)", 2D) = "white" {}
		DepthTexture ("DepthTexture", 2D) = "white" {}
		DepthRangeRed("DepthRangeRed",Range(0,255)) = 10
		DepthRangeGreen("DepthRangeGreen",Range(0,255)) = 100
		DepthRangeBlue("DepthRangeBlue",Range(0,1000)) = 1000
		SphereX("SphereX",Range(-2,2)) = 0
		SphereY("SphereY",Range(-2,2)) = 0
		SphereZ("SphereZ",Range(-2,2)) = 0
		SphereRad("SphereRad",Range(0,1)) = 0.1
		CloudVoxelSize("CloudVoxelSize", Range(0,1) ) = 0.01
		CloudMaxDepth("CloudMaxDepth", Range(0,100) ) = 1		//	in world space
		DepthToWorld("DepthToWorld", Range(0,0.1) ) = 0.1		//	actually depth to local
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100
		Cull off

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float4 vertexlocal : TEXCOORD1;
			};
			

			//	scene
			sampler2D _MainTex;
			float4 _MainTex_ST;
			
			sampler2D DepthTexture;
			float4 DepthTexture_ST;
			sampler2D ColourTexture;
			float4 ColourTexture_ST;
			float DepthValue;
			float DepthRangeRed;
			float DepthRangeGreen;
			float DepthRangeBlue;
			float DepthRangeCamera;
	
			float4x4 cameraToWorldMatrix;
			float4 cameraPos;
			float4x4 projectionMatrixInv;


			float SphereX;
			float SphereY;
			float SphereZ;
			float SphereRad;
			float CloudVoxelSize;
			float CloudMaxDepth;
			float DepthToWorld;

				
			float GetDepth(float2 uv)
			{
				float4 Depth4 = tex2D( DepthTexture, uv );
				float Depth = 0;
				Depth += Depth4.x * DepthRangeRed;
				Depth += Depth4.y * DepthRangeGreen;
				Depth += Depth4.z * DepthRangeBlue;
				return Depth;
			}
			
			float GetDepthNormal(float2 uv)
			{
				return GetDepth( uv ) / (DepthRangeRed + DepthRangeGreen);
			}

			float3 VectorFromCoordsRad(float2 latlon)
			{
				//	http://en.wikipedia.org/wiki/N-vector#Converting_latitude.2Flongitude_to_n-vector
				float latitude = latlon.x;
				float longitude = latlon.y;
				float las = sin(latitude);
				float lac = cos(latitude);
				float los = sin(longitude);
				float loc = cos(longitude);
				
				return float3( los * lac, las, loc * lac );
			}
			#define M_PI 3.1415926535897932384626433832795f
#define PIf	M_PI

			float2 GetLatLong(float x,float y,float Width,float Height)
			{
				float xmul = 2.0;
				float xsub = 1.0;
				float ymul = 1.0;
				float ysub = 0.5;
				
				float xfract = x / Width;
				xfract *= xmul;
				
				//	float yfract = (Height - y) / Height;
				float yfract = (y) / Height;
				yfract *= ymul;
				
				float lon = ( xfract - xsub) * M_PI;
				float lat = ( yfract - ysub) * M_PI;
				return float2( lat, lon );
			}
			
			float3 GetEquirectView(float2 uv)
			{
				float2 LatLon = GetLatLong( uv.x, uv.y, 1, 1);
				return VectorFromCoordsRad( LatLon );
			}
			
			float3 GetPosition(float2 uv)
			{
				return GetEquirectView(uv) * GetDepth(uv);
			}
			
			float2 ViewToLatLon(float3 View3)
			{
				View3 = normalize(View3);
				//	http://en.wikipedia.org/wiki/N-vector#Converting_n-vector_to_latitude.2Flongitude
				float x = View3.x;
				float y = View3.y;
				float z = View3.z;
	
			//	auto lat = tan2( x, z );
				float lat = atan( x/z );
				
				//	normalise y
				float xz = sqrt( (x*x) + (z*z) );
				float normy = y / sqrt( (y*y) + (xz*xz) );
				float lon = sin( normy );
				//$lon = atan2( $y, $xz );
				
				//	stretch longitude...
				lon *= 2.0;
				
				return float2( lat, lon );
			}
			float2 LatLonToUv(float2 LatLon,float Width,float Height)
			{
				//	-pi...pi -> -1...1
				float lat = LatLon.x;
				float lon = LatLon.y;
				lat /= PIf;
				lon /= PIf;
				
				//	-1..1 -> 0..2
				lat += 1.0;
				lon += 1.0;
				
				//	0..2 -> 0..1
				lat /= 2.0;
				lon /= 2.0;
				
				lon = 1.0 - lon;
				lat *= Width;
				lon *= Height;
				
				return float2( lat, lon );
			}
			//	3D view normal to equirect's UV
			float2 ViewToUv(float3 ViewDir)
			{
				float2 latlon = ViewToLatLon( ViewDir );
				latlon = LatLonToUv( latlon, 1, 1 );
				latlon.y = 1-latlon.y;
				return latlon;
			}
				
			float4 Debug_Normal(float3 Normal)
			{
				float3 CameraView = normalize(Normal);
				CameraView += 1.0f;
				CameraView /= 2.0f;
				return float4( CameraView.x, CameraView.y, CameraView.z, 1 );
			}
			
			float4 Debug_UvToEquirect(float2 uv)
			{
				return Debug_Normal( GetEquirectView( uv ) );
			}
			
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.vertexlocal = v.vertex;
				return o;
			}
			
			float mix(float val,float min, float max)
			{
				return (val-min) / (max-min);
			}
			
			float RadToDeg(float Rad)
			{
				return Rad * (360.0f / (M_PI * 2.0f) );
			 }
			 
			 //	http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
			 float sdSphere( float3 p, float s )
			{
				  return length(p)-s;
			}

			float4 GetColourDistance_TestSphere(float3 CloudPos)
			{
				//	test sphere
				float4 Sphere = float4(SphereX,SphereY,SphereZ,SphereRad);
				float3 SpherePos = Sphere.xyz;
				float3 SphereToCloud = CloudPos-SpherePos;
				float Dist = sdSphere(SphereToCloud,Sphere.w);
				if (  Dist > Sphere.w )
					return float4(0,0,0,9999);
					
				//	calc world pos of the point we hit
				/*
				float4 WorldIntersectPos = mul( _Object2World, float4(CloudPos,0) );
				float4 WorldSpherePos = mul( _Object2World, float4(SpherePos,0) );
				float3 Normal = normalize(WorldIntersectPos - WorldSpherePos);
				*/
				//	calc norm of the point we hit
				float3 Normal = normalize(SphereToCloud);
				Normal += 1;
				Normal /= 2;
				
							
				float d = Dist/SphereRad;
				return float4(d,d,d,Dist);
				return float4(Normal.x,Normal.y,Normal.z,Dist);
			}
			
			float4 GetColourDistance_DepthMap(float3 VolumePos)
			{
				//	need to work out the ray from the center of the 360 to the cloud point
				float3 CloudCenter = float3(SphereX,SphereY,SphereZ);
				float3 VolumeView3 = normalize(VolumePos-CloudCenter);
				//	convert view to equirect position to get the ray from the 360
				
				//float2 EquirectUv = ViewToLatLon( CameraView.zyx );
				float2 EquirectUv = ViewToUv( VolumeView3.xyz );
							
				
				//return float4( EquirectUv.x, EquirectUv.y, 0, 1 );
				float3 CloudColour = tex2D( _MainTex, EquirectUv );	
				//CloudColour = float3( EquirectUv.x, EquirectUv.y, 0 );
				
				if ( EquirectUv.x < 0 || EquirectUv.x > 1 )
					CloudColour = float3(0,1,1);
	
				float CloudDepth = GetDepth( EquirectUv );
				
				if ( CloudDepth > CloudMaxDepth )
					return float4(0,0,0,9999);
				
				CloudDepth *= DepthToWorld;
				float3 CloudPos = CloudCenter + VolumeView3*CloudDepth;
				float4 CloudSphere = float4( CloudPos, CloudVoxelSize );
				float Dist = sdSphere( VolumePos - CloudSphere.xyz, CloudSphere.w );
				if (  Dist > CloudSphere.w )
					return float4(0,0,0,9999);
				return float4( CloudColour, Dist );
			}
			
			//	return colour(xyz) & distance(w) to the nearest point in the cloud world to CloudPos
			float4 GetColourDistance(float3 VolumePos)
			{
				return GetColourDistance_DepthMap( VolumePos );
				return GetColourDistance_TestSphere( VolumePos );
	
			}

			float4 frag (v2f i) : COLOR
			{
				//	get ray inside us
				float3 RayDirection = normalize(WorldSpaceViewDir( i.vertexlocal ));
				//float3 RayDirection = normalize(ObjSpaceViewDir( i.vertexlocal ));
				float3 RayPosition = i.vertexlocal;
			
				
				float d = 999;
				float3 rgb = float3(1,0,0);;
				//	ray march
				
				#define MARCHES 100
				RayDirection *= 1.0f/MARCHES;
				for ( int i=0;	i<MARCHES;	i++ )
				{
					float3 Pos = RayPosition + (RayDirection*i);
					
					float4 RayColourDist = GetColourDistance( Pos );
					if ( RayColourDist.w > d )
						continue;
					
					//	gr: lerp colour? mult if we go back to front for alphas
					d = RayColourDist.w;
					rgb = RayColourDist.xyz;
					
				}
				
				if ( d > 1 )
					discard;
				d = 1-d;
				return float4(rgb.x,rgb.y,rgb.z,1);
			}
			ENDCG
		}
	}
}
