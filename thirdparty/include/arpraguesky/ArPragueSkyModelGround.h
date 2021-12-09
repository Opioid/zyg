/*
This source is published under the following 3-clause BSD license.

Copyright (c) 2021 the authors of the SIGGRAPH paper
"A Fitted Radiance and Attenuation Model for Realistic Atmospheres"
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * None of the names of the contributors may be used to endorse or promote
      products derived from this software without specific prior written
      permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/* ============================================================================

1.1   September 6th, 2021
      Added the hitherto forgotten licensing information to the file. It is
      of course under the same license as the full spherical model, see
      above for details.

1.0   March 3rd, 2021
      Initial release

============================================================================ */

#ifndef _ARPRAGUESKYMODELGROUND_H_
#define _ARPRAGUESKYMODELGROUND_H_

/*
Prague Sky Model, ground level version, 5.3.2021

Provides sky radiance, solar radiance and transmittance values for rays going from the ground into the upper hemisphere. 

Sky appearance is parametrized by:
- elevation = solar elevation in radians (angle between diretion to sun and ground plane), supported values in range [-0.073304, 1.570796] (corrsponds to [-4.2, 90] degrees)
- visibility = meteorological range in km (how far one can see), supported values in range [20, 131.8] (corresponds to turbity range [3.7, 1.37])
- albedo = ground albedo, supported values in range [0, 1]

Usage:
1. First call arpragueskymodelground_state_alloc_init to get initialized model state
2. Then to compute sky radiance, solar radiance or transmittance use the model state when calling arpragueskymodelground_sky_radiance, arpragueskymodelground_solar_radiance or arpragueskymodelground_transmittance, respectively
3. Finally call arpragueskymodelground_state_free to free used memory

Model query parameters:
- theta = angle between view direction and direction to zenith in radians, supported values in range [0, PI]
- gamma = angle between view direction and direction to sun in radians, supported values in range [0, PI]
- shadow = angle between view direction and direction perpendicular to a shadow plane (= direction to sun rotated PI/2 towards direction to zenith) in radians, used for negative solar elevations only, supported values in range [0, PI]
- wavelength = in nm, supported values in range [320, 760]
- distance = length of a ray segment (going from view point along view direction) for which transmittance should be evaluated, supported values in range [0, +inf]

Differences to Hosek model:
- uses visibility instead of turbidity (but visibility can be computed from turbidity as: visibility = 7487.f * exp(-3.41f * turbidity) + 117.1f * exp(-0.4768f * turbidity))
- supports negative solar elevations but for that requires additional parameter, the shadow angle (can be computed using the arpragueskymodelground_compute_angles function, unused for nonnegative solar elevations)
*/

#ifndef MATH_PI
#define MATH_PI                    3.141592653589793
#endif

#ifndef MATH_RAD_TO_DEG
#define MATH_RAD_TO_DEG            ( 180.0 / MATH_PI )
#endif

#ifndef MATH_DEG_TO_RAD
#define MATH_DEG_TO_RAD            ( MATH_PI / 180.0)
#endif

#define PSMG_SUN_RADIUS             0.2667 * MATH_DEG_TO_RAD
#define PSMG_PLANET_RADIUS          6378000.0
#define PSMG_PLANET_RADIUS_SQR      PSMG_PLANET_RADIUS * PSMG_PLANET_RADIUS
#define PSMG_ATMO_WIDTH             100000.0

typedef struct ArPragueSkyModelGroundState
{
	// Radiance metadata

	int visibilities;
	double * visibility_vals;

	int albedos;
	double * albedo_vals;
	
	int altitudes;
	double * altitude_vals;

	int elevations;
	double * elevation_vals;

	int channels;
	double channel_start;
	double channel_width;

	int tensor_components;

	int sun_nbreaks;
	int sun_offset;
	int sun_stride;
	double * sun_breaks;

	int zenith_nbreaks;
	int zenith_offset;
	int zenith_stride;
	double * zenith_breaks;

	int emph_nbreaks;
	int emph_offset;
	double * emph_breaks;

	int total_coefs_single_config;
	int total_coefs_all_configs;
	int total_configs;

	// Radiance data

	double * radiance_dataset;

    // Tranmittance metadata

	int     trans_n_a;
	int     trans_n_d;
	int     trans_visibilities;
	int     trans_altitudes;
	int     trans_rank;
	float * transmission_altitudes;
	float * transmission_visibilities;

    // Tranmittance data

	float * transmission_dataset_U;
	float * transmission_dataset_V;
	
	// Configuration
	
	double elevation;
	double visibility;
    double albedo;
}
ArPragueSkyModelGroundState;

// Initializes state of the model and returns it. Must be called before calling other functions. Expects full path to the file with model dataset.
ArPragueSkyModelGroundState  * arpragueskymodelground_state_alloc_init(
	const char                   * path_to_dataset,
	const double                   elevation,
	const double                   visibility,
	const double                   albedo
	);

// Free memory used by the model.
void arpragueskymodelground_state_free(
	ArPragueSkyModelGroundState        * state
	);

// Helper function that computes angles required by the model given the current configuration. Expects:
// - solar elevation at view point in radians
// - solar azimuth at view point in radians
// - view direction as an array of 3 doubles
// - direction to zenith as an array of 3 doubles (e.g. {0.0, 0.0, 1.0} or an actual direction to zenith based on true view point position on the planet)
void arpragueskymodelground_compute_angles(
	const double		           sun_elevation,
	const double		           sun_azimuth,
	const double		         * view_direction,
	const double		         * up_direction,
		  double                 * theta,
		  double                 * gamma,
		  double                 * shadow
	);

// Computes sky radiance arriving at view point.
double arpragueskymodelground_sky_radiance(
	const ArPragueSkyModelGroundState  * state,
	const double                   theta,
	const double                   gamma,
	const double                   shadow,
	const double                   wavelength
	);

// Computes solar radiance arriving at view point (i.e. including transmittance trough the atmosphere).
double arpragueskymodelground_solar_radiance(
	const ArPragueSkyModelGroundState  * state,
	const double                   theta,
	const double                   wavelength
	);

// Computes transmittance along a ray segment of a given length going from view point along view direction. Could be used e.g. for computing attenuation of radiance coming from the nearest intersection with scene geometry or of radiance coming outside of the atmoshere (just use huge value for the distance parameter, it's how it is internally done for the solar radiance).
double arpragueskymodelground_transmittance(
	const ArPragueSkyModelGroundState  * state,
	const double                   theta,
	const double                   wavelength,
	const double                   distance
	);

#endif // _ARPRAGUESKYMODELGROUND_H_
