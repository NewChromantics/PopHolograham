using UnityEngine;
using System.Collections;

public class RotateWithTouchpad : MonoBehaviour {

	[Range(0,50)]
	public float			mRotationScalarPitch = 1;

	[Range(0,50)]
	public float			mRotationScalarYaw = 1;

	void Update () {
	
		float RotationYaw = Input.GetAxis ("Mouse X");
		Debug.Log ("Rotation yaw " + RotationYaw);
		float RotationPitch = Input.GetAxis ("Mouse Y");
		RotationPitch *= mRotationScalarPitch;
		RotationYaw *= mRotationScalarYaw;
		this.transform.Rotate ( new Vector3 (0, RotationYaw, RotationPitch) );

	}
}
