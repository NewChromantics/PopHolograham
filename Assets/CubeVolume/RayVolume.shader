﻿Shader "NewChromantics/RayVolume"
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
		CloudVoxelSize("CloudVoxelSize", Range(0,0.2) ) = 0.01
		CloudMaxDepth("CloudMaxDepth", Range(0,400) ) = 1		//	in world space
		CloudMinDepth("CloudMinDepth", Range(-1,400) ) = 0		//	in world space
		DepthToWorld("DepthToWorld", Range(0,0.2) ) = 0.1		//	actually depth to local
		CameraFovHorz("CameraFovHorz", Range(0,360) ) = 360
		CameraFovTop("CameraFovTop", Range(0,360) ) = 0
		CameraFovBottom("CameraFovBottom", Range(0,360) ) = 360
		DepthMult("DepthMult", Range(0,1) ) = 0
		LocalRayNearDepth("LocalRayNearDepth", Range(0,1.2) ) = 0	//	sqrt(1+1)
		LocalRayFarDepth("LocalRayFarDepth", Range(0,1.414) ) = 1.414	//	sqrt(1+1)
	}
	SubShader
	{
		Tags { "RenderType"="Transparent" }
		LOD 100
		Cull off

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			#define DRAW_EQUIRECT		0
			#define DRAW_NORMAL			0
			#define DRAW_DOTFORWARD		0
			#define DRAW_DOTUP			0
			//#define DRAW_AS_SPHERE	0.3f
			#define DEBUG_CAMERA_NORMAL	0
			#define DRAW_DEBUG_EQUIRECT	0
			#define DEBUG_TEXTURES		0
			#define DEBUG_CAMERA_DIR	0

#define PIf	3.1415926535897932384626433832795f

			#define TEST_GLES_MODE
			#if defined(TEST_GLES_MODE) || defined(SHADER_API_GLES) || defined(SHADER_API_GLES3)
				#define TARGET_MOBILE
			#endif
			

			//#define MODIFY_DEPTH

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct TVertOut
			{
				float2 uv : TEXCOORD0;
				float4 vertexlocal : TEXCOORD1;
				float4 vertex : SV_POSITION;
			};
			
			//	http://docs.unity3d.com/Manual/SL-ShaderSemantics.html
			struct TFragOut
			{
				float4 rgba : SV_Target;	//	COLOR
				#if defined(MODIFY_DEPTH)
				float depth : SV_Depth;	//	DEPTH
				#endif
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
			float CameraFovHorz;
			float CameraFovTop;
			float CameraFovBottom;
			float DepthMult;
	
			float4x4 cameraToWorldMatrix;
			float4 cameraPos;
			float4x4 projectionMatrixInv;


			float SphereX;
			float SphereY;
			float SphereZ;
			float SphereRad;
			float CloudVoxelSize;
			float CloudMaxDepth;
			float CloudMinDepth;
			float DepthToWorld;
			float LocalRayNearDepth;
			float LocalRayFarDepth;

			float RadToDeg(float Rad)
			{
				return Rad * (360.0f / (PIf * 2.0f) );
			}
			float DegToRad(float Deg)
			{
				return Deg * ((PIf * 2.0f)/360.0f );
			}
			 
				
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
				
				float lon = ( xfract - xsub) * PIf;
				float lat = ( yfract - ysub) * PIf;
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
			
			float Range(float Min,float Max,float Time)
			{
				return (Time-Min) / (Max-Min);
			}
			
			//	y = visible
			float2 RescaleFov(float Radians,float MinDegrees,float MaxDegrees)
			{
				float Deg = RadToDeg( Radians );
				Deg += 180;
				
				//	re-scale
				Deg = Range( MinDegrees, MaxDegrees, Deg );
				bool Visible = Deg >= 0 && Deg <= 1;
				Deg *= 360;
				
				Deg -= 180;
				Radians = DegToRad( Deg );
				
				return float2( Radians, Visible?1:0 );
			}
			
			float3 ViewToLatLonVisible(float3 View3)
			{
				View3 = normalize(View3);
				//	http://en.wikipedia.org/wiki/N-vector#Converting_n-vector_to_latitude.2Flongitude
				float x = View3.x;
				float y = View3.y;
				float z = View3.z;
	
			//	auto lat = tan2( x, z );
				float lat = atan2( x, z );
				
				//	normalise y
				float xz = sqrt( (x*x) + (z*z) );
				float normy = y / sqrt( (y*y) + (xz*xz) );
				float lon = sin( normy );
				//float lon = atan2( y, xz );
				
				//	stretch longitude...
				//	gr: removed this as UV was wrapping around
				//lon *= 2.0;
				//	gr: sin output is -1 to 1...
				lon *= PIf;
				
				bool Visible = true;
				float2 NewLat = RescaleFov( lat, 0, CameraFovHorz );
				float2 NewLon = RescaleFov( lon, CameraFovTop, CameraFovBottom );
				lat = NewLat.x;
				lon = NewLon.x;
				Visible = (NewLat.y*NewLon.y) > 0;
				
	
				return float3( lat, lon, Visible ? 1:0 );
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
								
				lat *= Width;
				lon *= Height;
				
				return float2( lat, lon );
			}
			//	3D view normal to equirect's UV. Z is 0 if invalid
			float3 ViewToUvVisible(float3 ViewDir)
			{
				float3 latlonVisible = ViewToLatLonVisible( ViewDir );
				latlonVisible.xy = LatLonToUv( latlonVisible.xy, 1, 1 );
				return latlonVisible;
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
			
			TVertOut vert (appdata v)
			{
				TVertOut o;
				o.vertex = mul(UNITY_MATRIX_MVP, v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.vertexlocal = v.vertex;
				return o;
			}
			
			float mix(float val,float min, float max)
			{
				return (val-min) / (max-min);
			}
			
			 //	http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
			 float sdSphere( float3 p, float s )
			{
				  return length(p)-s;
			}

			float4 GetColourDistance_TestSphere(float3 CloudPos,float3 CameraPosVolume)
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
			
			float4 GetColourDistance_DepthMap(float3 VolumePos,float3 CameraPosVolume)
			{
				//	need to work out the ray from the center of the 360 to the cloud point
				float3 CloudCenter = float3(SphereX,SphereY,SphereZ);
				float3 VolumeView3 = VolumePos-CloudCenter;
				//if ( length( VolumeView3.xyz ) < 0.1 )
				//	return float4(0,0,0,9999);
				VolumeView3 = normalize(VolumeView3);
				
				//	convert view to equirect position to get the ray from the 360
				float3 EquirectUvVisible = ViewToUvVisible( VolumeView3.xyz );
				if ( EquirectUvVisible.z < 1 )
					return float4(0,0,0,9999);
					
				float2 EquirectUv = EquirectUvVisible.xy;
				//if ( EquirectUv.x < 0.5f )	return float4(0,0,0,9999);
				
				//return float4( EquirectUv.x, EquirectUv.y, 0, 1 );
				float3 CloudColour = tex2D( _MainTex, EquirectUv );	
				#if DRAW_EQUIRECT
					CloudColour = float3( EquirectUv.x, EquirectUv.y, 0 );
				#endif
				#if DRAW_NORMAL
					CloudColour = Debug_Normal( CloudColour ).xyz;
				#endif
				#if DRAW_DOTFORWARD 
					CloudColour = dot( VolumeView3, float3(0,0,1) );
				#endif
				#if DRAW_DOTUP
					CloudColour = dot( VolumeView3, float3(0,1,0) );
				#endif
				//	gr: why do all view vectors point down?
				//CloudColour.xyz = dot( VolumeView3, float3(0,-1,0) );
				
				#if DRAW_DEBUG_EQUIRECT
				if ( EquirectUv.x < 0 || EquirectUv.x > 1.0f )
					CloudColour = float3(0,1,1);
				if ( EquirectUv.y < 0 || EquirectUv.y > 1.0f )
					CloudColour = float3(1,1,0);
				#endif
				
				float CloudDepth = GetDepth( EquirectUv );
				
				
				if ( CloudDepth < CloudMinDepth || CloudDepth > CloudMaxDepth )
					return float4(0,0,0,9999);
				
				CloudDepth *= DepthToWorld;
				
				#if defined(DRAW_AS_SPHERE)
					CloudDepth = DRAW_AS_SPHERE;
				#endif
				
				float3 CloudPos = CloudCenter + VolumeView3*CloudDepth;
				float4 CloudSphere = float4( CloudPos, CloudVoxelSize );
				float Dist = sdSphere( VolumePos - CloudSphere.xyz, CloudSphere.w );
				if (  Dist > CloudSphere.w )
					return float4(0,0,0,9999);
				Dist = length( CameraPosVolume - CloudSphere.xyz );
				return float4( CloudColour, Dist );
			}
			
			//	return colour(xyz) & distance(w) to the nearest point in the cloud world to CloudPos
			float4 GetColourDistance(float3 VolumePos,float3 CameraPosVolume)
			{
				return GetColourDistance_DepthMap( VolumePos, CameraPosVolume );
				return GetColourDistance_TestSphere( VolumePos, CameraPosVolume );
	
			}
			/* unity.cginc
			// Z buffer to linear depth
			inline float LinearEyeDepth( float z )
			{
				return 1.0 / (_ZBufferParams.z * z + _ZBufferParams.w);
			}
			*/
			
			// Z buffer to linear depth
			//	gr: linear depth to z buffer
			//	http://stackoverflow.com/a/6657284/355753
			inline float EyeDepthToZBuffer( float linearDepth )
			{
				float zFar = _ZBufferParams.w;
				float zNear= _ZBufferParams.z;
				/*
				float A = zFar;
    			float B = zNear;
    			return 0.5*(-A*linearDepth + B) / linearDepth + 0.5;
    			*/
    			float nonLinearDepth = (zFar + zNear - 2.0 * zNear * zFar / linearDepth) / (zFar - zNear);
  				nonLinearDepth = (nonLinearDepth + 1.0) / 2.0;
  				return nonLinearDepth;
    		}
		
			TFragOut frag (TVertOut input)
			{
				TFragOut fragout;
				
				//	get ray inside us
				float4 CameraPos4 = float4( _WorldSpaceCameraPos, 1 );
				float3 CameraPosLocal = mul( _World2Object, CameraPos4 );
				//float3 RayDirection = normalize(WorldSpaceViewDir( i.vertexlocal ));
				float3 RayDirection = normalize(ObjSpaceViewDir( input.vertexlocal ));
				float3 RayPosition = input.vertexlocal;
				//	we want ray AWAY from the camera
				RayDirection *= -1;
				
				
				#if DEBUG_TEXTURES
				{
					if ( input.uv.y < 0.5 )
					{
						fragout.rgba = tex2D( _MainTex, float2( input.uv.x, Range( 0, 0.5, input.uv.y ) ) );
					}
					else
					{
						fragout.rgba = tex2D( DepthTexture, float2( input.uv.x, Range( 0.5, 1.0, input.uv.y ) ) );
					}
					return fragout;
				}
				#endif
		

				#if DEBUG_CAMERA_DIR
				{
					fragout.rgba = Debug_Normal( RayDirection );
					return fragout;
				}
				#endif
			
			//#error 1) Equirect is wrapping
			//#error 2) distance returned in GetColourDistance is closer, the further away it is (break proves this)
				
				float d = 99;
				float3 rgb = float3(1,0,0);;
				//	ray march
				
				//	start BEHIND for when we're INSIDE the bounds (gr: this may only apply to the debug sphere)
				#if defined(TARGET_MOBILE)
					#define FORWARD_MARCHES		10
					#define BACKWARD_MARCHES	4
				#else
					#define FORWARD_MARCHES		80
					#define BACKWARD_MARCHES	40
				#endif
				for ( int i=-BACKWARD_MARCHES;	i<FORWARD_MARCHES;	i++ )
				{
					float RayLocalDepth = lerp( LocalRayNearDepth, LocalRayFarDepth, (i/(float)FORWARD_MARCHES) );
					float3 Pos = RayPosition + (RayDirection*RayLocalDepth);
					
					float4 RayColourDist = GetColourDistance( Pos, CameraPosLocal );
					
					//	further than current best
					if ( RayColourDist.w >= d )
						continue;
					
					//	gr: lerp colour? mult if we go back to front for alphas
					d = RayColourDist.w;
					//d = RayLocalDepth;
					rgb = RayColourDist.xyz;
					
					//	gr: don't leave this in! testing speed
					#if defined(TARGET_MOBILE)
						break;
					#endif
				}
				
				//	gr: d is now relative to camera-local, so can be > 1
				float LocalFar = LocalRayFarDepth;
				float MaxLength = distance( CameraPosLocal.xyz, input.vertexlocal ) + LocalFar;
				if ( d > MaxLength )
					discard;
				
				#if DEBUG_CAMERA_NORMAL
					rgb = Debug_Normal(RayDirection);
				#endif
				
				fragout.rgba = float4(rgb.x,rgb.y,rgb.z,0.5f);
				//fragout.rgba = float4(d,d,d,0.5f);
				
				#if defined(MODIFY_DEPTH)
				//	work out depth from camera
				float3 ViewPos = RayPosition + (RayDirection*d);
				d = length( CameraPosLocal - ViewPos );
				//	brighter = nearer
				//d = 1 - (d/ MaxLength);
				//return float4(d,d,d,1);

								//	depth should be clipspace.z / w
				//	http://forum.unity3d.com/threads/how-to-know-distance-from-camera-in-fragmentshader.369050/
				//fragout.depth = i.vertex.z / i.vertex.w;
				fragout.depth = EyeDepthToZBuffer(d);
				#endif
				return fragout;
			}
			ENDCG
		}
	}
}
