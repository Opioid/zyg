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

#include "ArPragueSkyModelGround.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

//   Some macro definitions that occur elsewhere in ART, and that have to be
//   replicated to make this a stand-alone module.

#ifndef ALLOC
#define ALLOC(_struct)                ((_struct *)malloc(sizeof(_struct)))
#endif

#ifndef ALLOC_ARRAY
#define ALLOC_ARRAY(_struct, _number) ((_struct *)malloc(sizeof(_struct) * (_number)))
#endif

#ifndef FREE
#define FREE(_pointer) \
do { \
    void *_ptr=(void *)(_pointer); \
    free(_ptr); \
    _ptr=NULL; \
    _pointer=NULL; \
} while (0)
#endif

#ifndef MATH_MAX
#define MATH_MAX(_a, _b)                 ((_a) > (_b) ? (_a) : (_b))
#endif

#ifndef MATH_HUGE_DOUBLE
#define MATH_HUGE_DOUBLE        5.78960446186580977117855E+76
#endif

double arpragueskymodelground_double_from_half(const unsigned short value)
{
	unsigned long hi = (unsigned long)(value&0x8000) << 16;
	unsigned int abs = value & 0x7FFF;
	if(abs)
	{
		hi |= 0x3F000000 << (unsigned)(abs>=0x7C00);
		for(; abs<0x400; abs<<=1,hi-=0x100000) ;
		hi += (unsigned long)(abs) << 10;
	}
	unsigned long dbits = (unsigned long)(hi) << 32;
	double out;
	memcpy(&out, &dbits, sizeof(double));
	return out;
}

int arpragueskymodelground_compute_pp_coefs_from_half(const int nbreaks, const double * breaks, const unsigned short * values, double * coefs, const int offset, const double scale)
{
	for (int i = 0; i < nbreaks - 1; ++i)
	{
		const double val1 = arpragueskymodelground_double_from_half(values[i+1]) / scale;
		const double val2 = arpragueskymodelground_double_from_half(values[i]) / scale;
		const double diff = val1 - val2;

		coefs[offset + 2 * i] = diff / (breaks[i+1] - breaks[i]);
		coefs[offset + 2 * i + 1]  = val2;
	}
	return 2 * nbreaks - 2;
}

void arpragueskymodelground_print_error_and_exit(const char * message) 
{
	fprintf(stderr, message);
	fprintf(stderr, "\n");
	fflush(stderr);
	exit(-1);
}

void arpragueskymodelground_read_radiance(ArPragueSkyModelGroundState * state, FILE * handle)
{
	// Read metadata

	// Structure of the metadata part of the data file:
	// visibilities      (1 * int),  visibility_vals (visibilities * double),
	// albedos           (1 * int),  albedo_vals    (albedos * double),
	// altitudes         (1 * int),  altitude_vals  (altitudes * double),
	// elevations        (1 * int),  elevation_vals (elevations * double),
	// channels          (1 * int),  channel_start  (1 * double), channel_width (1 * double),
	// tensor_components (1 * int),
    // sun_nbreaks       (1 * int),  sun_breaks     (sun_nbreaks * double),
	// zenith_nbreaks    (1 * int),  zenith_breaks  (zenith_nbreaks * double),
	// emph_nbreaks      (1 * int),  emph_breaks    (emph_nbreaks * double)

	int vals_read;

	vals_read = fread(&state->visibilities, sizeof(int), 1, handle);
	if (vals_read != 1 || state->visibilities < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: visibilities");

	state->visibility_vals = ALLOC_ARRAY(double, state->visibilities);
	vals_read = fread(state->visibility_vals, sizeof(double), state->visibilities, handle);
	if (vals_read != state->visibilities) arpragueskymodelground_print_error_and_exit("Error reading sky model data: visibility_vals");

	vals_read = fread(&state->albedos, sizeof(int), 1, handle);
	if (vals_read != 1 || state->albedos < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: albedos");

	state->albedo_vals = ALLOC_ARRAY(double, state->albedos);
	vals_read = fread(state->albedo_vals, sizeof(double), state->albedos, handle);
	if (vals_read != state->albedos) arpragueskymodelground_print_error_and_exit("Error reading sky model data: albedo_vals");

	vals_read = fread(&state->altitudes, sizeof(int), 1, handle);
	if (vals_read != 1 || state->altitudes < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: altitudes");

	state->altitude_vals = ALLOC_ARRAY(double, state->altitudes);
	vals_read = fread(state->altitude_vals, sizeof(double), state->altitudes, handle);
	if (vals_read != state->altitudes) arpragueskymodelground_print_error_and_exit("Error reading sky model data: altitude_vals");

	vals_read = fread(&state->elevations, sizeof(int), 1, handle);
	if (vals_read != 1 || state->elevations < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: elevations");

	state->elevation_vals = ALLOC_ARRAY(double, state->elevations);
	vals_read = fread(state->elevation_vals, sizeof(double), state->elevations, handle);
	if (vals_read != state->elevations) arpragueskymodelground_print_error_and_exit("Error reading sky model data: elevation_vals");

	vals_read = fread(&state->channels, sizeof(int), 1, handle);
	if (vals_read != 1 || state->channels < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: channels");

	vals_read = fread(&state->channel_start, sizeof(double), 1, handle);
	if (vals_read != 1 || state->channel_start < 0) arpragueskymodelground_print_error_and_exit("Error reading sky model data: channel_start");

	vals_read = fread(&state->channel_width, sizeof(double), 1, handle);
	if (vals_read != 1 || state->channel_width <= 0) arpragueskymodelground_print_error_and_exit("Error reading sky model data: channel_width");

	vals_read = fread(&state->tensor_components, sizeof(int), 1, handle);
	if (vals_read != 1 || state->tensor_components < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: tensor_components");

	vals_read = fread(&state->sun_nbreaks, sizeof(int), 1, handle);
	if (vals_read != 1 || state->sun_nbreaks < 2) arpragueskymodelground_print_error_and_exit("Error reading sky model data: sun_nbreaks");

	state->sun_breaks = ALLOC_ARRAY(double, state->sun_nbreaks);
	vals_read = fread(state->sun_breaks, sizeof(double), state->sun_nbreaks, handle);
	if (vals_read != state->sun_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: sun_breaks");

	vals_read = fread(&state->zenith_nbreaks, sizeof(int), 1, handle);
	if (vals_read != 1 || state->zenith_nbreaks < 2) arpragueskymodelground_print_error_and_exit("Error reading sky model data: zenith_nbreaks");

	state->zenith_breaks = ALLOC_ARRAY(double, state->zenith_nbreaks);
	vals_read = fread(state->zenith_breaks, sizeof(double), state->zenith_nbreaks, handle);
	if (vals_read != state->zenith_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: zenith_breaks");

	vals_read = fread(&state->emph_nbreaks, sizeof(int), 1, handle);
	if (vals_read != 1 || state->emph_nbreaks < 2) arpragueskymodelground_print_error_and_exit("Error reading sky model data: emph_nbreaks");

	state->emph_breaks = ALLOC_ARRAY(double, state->emph_nbreaks);
	vals_read = fread(state->emph_breaks, sizeof(double), state->emph_nbreaks, handle);
	if (vals_read != state->emph_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: emph_breaks");

	// Calculate offsets and strides

	state->sun_offset = 0;
	state->sun_stride = 2 * state->sun_nbreaks - 2 + 2 * state->zenith_nbreaks - 2;

	state->zenith_offset = state->sun_offset + 2 * state->sun_nbreaks - 2;
	state->zenith_stride = state->sun_stride;

	state->emph_offset = state->sun_offset + state->tensor_components * state->sun_stride;

	state->total_coefs_single_config = state->emph_offset + 2 * state->emph_nbreaks - 2;
	state->total_configs = state->channels * state->elevations * state->altitudes * state->albedos * state->visibilities;
	state->total_coefs_all_configs = state->total_coefs_single_config * state->total_configs;

	// Read data

	// Structure of the data part of the data file:
	// [[[[[[ sun_coefs (sun_nbreaks * half), zenith_scale (1 * double), zenith_coefs (zenith_nbreaks * half) ] * tensor_components, emph_coefs (emph_nbreaks * half) ]
	//   * channels ] * elevations ] * altitudes ] * albedos ] * visibilities

	int offset = 0;
	state->radiance_dataset = ALLOC_ARRAY(double, state->total_coefs_all_configs);

	unsigned short * radiance_temp = ALLOC_ARRAY(unsigned short, MATH_MAX(state->sun_nbreaks, MATH_MAX(state->zenith_nbreaks, state->emph_nbreaks)));

	for (int con = 0; con < state->total_configs; ++con)
	{
		for (int tc = 0; tc < state->tensor_components; ++tc)
		{
			const double sun_scale = 1.0;
			vals_read = fread(radiance_temp, sizeof(unsigned short), state->sun_nbreaks, handle);
			if (vals_read != state->sun_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: sun_coefs");
			offset += arpragueskymodelground_compute_pp_coefs_from_half(state->sun_nbreaks, state->sun_breaks, radiance_temp, state->radiance_dataset, offset, sun_scale);

			double zenith_scale;
			vals_read = fread(&zenith_scale, sizeof(double), 1, handle);
			if (vals_read != 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: zenith_scale");

			vals_read = fread(radiance_temp, sizeof(unsigned short), state->zenith_nbreaks, handle);
			if (vals_read != state->zenith_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: zenith_coefs");
			offset += arpragueskymodelground_compute_pp_coefs_from_half(state->zenith_nbreaks, state->zenith_breaks, radiance_temp, state->radiance_dataset, offset, zenith_scale);
		}

		const double emph_scale = 1.0;
		vals_read = fread(radiance_temp, sizeof(unsigned short), state->emph_nbreaks, handle);
		if (vals_read != state->emph_nbreaks) arpragueskymodelground_print_error_and_exit("Error reading sky model data: emph_coefs");
		offset += arpragueskymodelground_compute_pp_coefs_from_half(state->emph_nbreaks, state->emph_breaks, radiance_temp, state->radiance_dataset, offset, emph_scale);
	}

	free(radiance_temp);
}

void arpragueskymodelground_read_transmittance(ArPragueSkyModelGroundState * state, FILE * handle)
{
	// Read metadata

	int vals_read;

	vals_read = fread(&state->trans_n_d, sizeof(int), 1, handle);
	if (vals_read != 1 || state->trans_n_d < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: trans_n_d");

	vals_read = fread(&state->trans_n_a, sizeof(int), 1, handle);
	if (vals_read != 1 || state->trans_n_a < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: trans_n_a");

	vals_read = fread(&state->trans_visibilities, sizeof(int), 1, handle);
	if (vals_read != 1 || state->trans_visibilities < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: trans_visibilities");

	vals_read = fread(&state->trans_altitudes, sizeof(int), 1, handle);
	if (vals_read != 1 || state->trans_altitudes < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: trans_altitudes");

	vals_read = fread(&state->trans_rank, sizeof(int), 1, handle);
	if (vals_read != 1 || state->trans_rank < 1) arpragueskymodelground_print_error_and_exit("Error reading sky model data: trans_rank");

	state->transmission_altitudes = ALLOC_ARRAY(float, state->trans_altitudes);
	vals_read = fread(state->transmission_altitudes, sizeof(float), state->trans_altitudes, handle);
	if (vals_read != state->trans_altitudes) arpragueskymodelground_print_error_and_exit("Error reading sky model data: transmission_altitudes");

	state->transmission_visibilities = ALLOC_ARRAY(float, state->trans_visibilities);
	vals_read = fread(state->transmission_visibilities, sizeof(float), state->trans_visibilities, handle);
	if (vals_read != state->trans_visibilities) arpragueskymodelground_print_error_and_exit("Error reading sky model data: transmission_visibilities");

	const int total_coefs_U = state->trans_n_d * state->trans_n_a * state->trans_rank * state->trans_altitudes;
	const int total_coefs_V = state->trans_visibilities * state->trans_rank * 11 * state->trans_altitudes;

	// Read data

	state->transmission_dataset_U = ALLOC_ARRAY(float, total_coefs_U);
	vals_read = fread(state->transmission_dataset_U, sizeof(float), total_coefs_U, handle);
	if (vals_read != total_coefs_U) arpragueskymodelground_print_error_and_exit("Error reading sky model data: transmission_dataset_U");

	state->transmission_dataset_V = ALLOC_ARRAY(float, total_coefs_V);
	vals_read = fread(state->transmission_dataset_V, sizeof(float), total_coefs_V, handle);
	if (vals_read != total_coefs_V) arpragueskymodelground_print_error_and_exit("Error reading sky model data: transmission_dataset_V");
}

ArPragueSkyModelGroundState  * arpragueskymodelground_state_alloc_init(
	const char                   * path_to_dataset,
	const double                   elevation,
	const double                   visibility,
	const double                   albedo
	)
{
	ArPragueSkyModelGroundState * state = ALLOC(ArPragueSkyModelGroundState);

	FILE * handle = fopen(path_to_dataset, "rb");

	// Read data
	arpragueskymodelground_read_radiance(state, handle);
	arpragueskymodelground_read_transmittance(state, handle);

	fclose(handle);
	
	state->elevation  = elevation;
	state->visibility = visibility;
	state->albedo     = albedo;

	return state;
}

void arpragueskymodelground_state_free(
	ArPragueSkyModelGroundState  * state
	)
{
	free(state->visibility_vals);
	free(state->albedo_vals);
	free(state->altitude_vals);
	free(state->elevation_vals);

	free(state->sun_breaks);
	free(state->zenith_breaks);
	free(state->emph_breaks);
	free(state->radiance_dataset);

	free(state->transmission_dataset_U);
	free(state->transmission_dataset_V);
	free(state->transmission_altitudes);
	free(state->transmission_visibilities);

	FREE(state);
}

void arpragueskymodelground_compute_angles(
	const double		           sun_elevation,
	const double		           sun_azimuth,
	const double		         * view_direction,
	const double		         * up_direction,
		  double                 * theta,
		  double                 * gamma,
		  double                 * shadow
        )
{
    // Zenith angle (theta)

    const double cosTheta = view_direction[0] * up_direction[0] + view_direction[1] * up_direction[1] + view_direction[2] * up_direction[2];
    *theta = acos(cosTheta);

    // Sun angle (gamma)

	const double sun_direction[] = {cos(sun_azimuth) * cos(sun_elevation), sin(sun_azimuth) * cos(sun_elevation), sin(sun_elevation)};
	const double cosGamma = view_direction[0] * sun_direction[0] + view_direction[1] * sun_direction[1] + view_direction[2] * sun_direction[2];
    *gamma = acos(cosGamma);

    // Shadow angle

    const double shadow_angle = sun_elevation + MATH_PI * 0.5;
	const double shadow_direction[] = {cos(shadow_angle) * cos(sun_azimuth), cos(shadow_angle) * sin(sun_azimuth), sin(shadow_angle)};
	const double cosShadow = view_direction[0] * shadow_direction[0] + view_direction[1] * shadow_direction[1] + view_direction[2] * shadow_direction[2];
    *shadow = acos(cosShadow);
}

double arpragueskymodelground_lerp(const double from, const double to, const double factor)
{
	return (1.0 - factor) * from + factor * to;
}

int arpragueskymodelground_find_segment(const double x, const int nbreaks, const double* breaks)
{
	int segment = 0;
	for (segment = 0; segment < nbreaks; ++segment)
	{
		if (breaks[segment+1] >= x)
		break;
	}
	return segment;
}

double arpragueskymodelground_eval_pp(const double x, const int segment, const double * breaks, const double * coefs)
{
	const double x0 = x - breaks[segment];
	const double * sc = coefs + 2 * segment; // segment coefs
	return sc[0] * x0 + sc[1];
}

const double * arpragueskymodelground_control_params_single_config(
	const ArPragueSkyModelGroundState * state,
	const double                * dataset,
	const int                     total_coefs_single_config,
	const int                     elevation,
	const int                     altitude,
	const int                     visibility,
	const int                     albedo,
	const int                     wavelength
)
{
	return dataset + (total_coefs_single_config * (
		wavelength +
		state->channels*elevation +
		state->channels*state->elevations*altitude +
		state->channels*state->elevations*state->altitudes*albedo +
		state->channels*state->elevations*state->altitudes*state->albedos*visibility
	));
}

double arpragueskymodelground_reconstruct(
	const ArPragueSkyModelGroundState  * state,
	const double                   gamma,
	const double                   alpha,
	const double                   theta,
	const int                      gamma_segment,
	const int                      alpha_segment,
	const int                      theta_segment,
	const double                 * control_params
)
{
  double res = 0.0;
  for (int t = 0; t < state->tensor_components; ++t) {
	const double sun_val_t = arpragueskymodelground_eval_pp(gamma, gamma_segment, state->sun_breaks, control_params + state->sun_offset + t * state->sun_stride);
	const double zenith_val_t = arpragueskymodelground_eval_pp(alpha, alpha_segment, state->zenith_breaks, control_params + state->zenith_offset + t * state->zenith_stride);
	res += sun_val_t * zenith_val_t;
  }
  const double emph_val_t = arpragueskymodelground_eval_pp(theta, theta_segment, state->emph_breaks, control_params + state->emph_offset);
  res *= emph_val_t;

  return MATH_MAX(res, 0.0);
}

double arpragueskymodelground_map_parameter(const double param, const int value_count, const double * values)
{
	double mapped;
	if (param < values[0])
	{
		mapped = 0.0;
	}
	else if (param > values[value_count - 1])
	{
		mapped = (double)value_count - 1.0;
	}
	else
	{
		for (int v = 0; v < value_count; ++v)
		{
			const double val = values[v];
			if (fabs(val - param) < 1e-6)
			{
				mapped = v;
				break;
			}
			else if (param < val)
			{
				mapped = v - ((val - param) / (val - values[v - 1]));
				break;
			}
		}
	}
	return mapped;
}


///////////////////////////////////////////////
// Sky radiance
///////////////////////////////////////////////


double arpragueskymodelground_interpolate_elevation(
	const ArPragueSkyModelGroundState  * state,
	double                  elevation,
	int                     altitude,
	int                     visibility,
	int                     albedo,
	int                     wavelength,
	double                  gamma,
	double                  alpha,
	double                  theta,
	int                     gamma_segment,
	int                     alpha_segment,
	int                     theta_segment
)
{
  const int elevation_low = (int)elevation;
  const double factor = elevation - (double)elevation_low;

  const double * control_params_low = arpragueskymodelground_control_params_single_config(
    state,
    state->radiance_dataset,
    state->total_coefs_single_config,
    elevation_low,
    altitude,
    visibility,
    albedo,
    wavelength);

  double res_low = arpragueskymodelground_reconstruct(
    state,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment,
    control_params_low);    

  if (factor < 1e-6 || elevation_low >= (state->elevations - 1))
  {
    return res_low;
  }

  const double * control_params_high = arpragueskymodelground_control_params_single_config(
    state,
    state->radiance_dataset,
    state->total_coefs_single_config,
    elevation_low+1,
    altitude,
    visibility,
    albedo,
    wavelength);

  double res_high = arpragueskymodelground_reconstruct(
    state,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment,
    control_params_high); 

  return arpragueskymodelground_lerp(res_low, res_high, factor);
}

double arpragueskymodelground_interpolate_altitude(
	const ArPragueSkyModelGroundState  * state,
	double                  elevation,
	double                  altitude,
	int                     visibility,
	int                     albedo,
	int                     wavelength,
	double                  gamma,
	double                  alpha,
	double                  theta,
	int                     gamma_segment,
	int                     alpha_segment,
	int                     theta_segment
)
{
  const int altitude_low = (int)altitude;
  const double factor = altitude - (double)altitude_low;

  double res_low = arpragueskymodelground_interpolate_elevation(
    state,
    elevation,
    altitude_low,
    visibility,
    albedo,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  if (factor < 1e-6 || altitude_low >= (state->altitudes - 1))
  {
    return res_low;
  }

  double res_high = arpragueskymodelground_interpolate_elevation(
    state,
    elevation,
    altitude_low + 1,
    visibility,
    albedo,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  return arpragueskymodelground_lerp(res_low, res_high, factor);
}

double arpragueskymodelground_interpolate_visibility(
	const ArPragueSkyModelGroundState  * state,
	double                  elevation,
	double                  altitude,
	double                  visibility,
	int                     albedo,
	int                     wavelength,
	double                  gamma,
	double                  alpha,
	double                  theta,
	int                     gamma_segment,
	int                     alpha_segment,
	int                     theta_segment
)
{
  const int visibility_low = (int)visibility;
  const double factor = visibility - (double)visibility_low;

  double res_low = arpragueskymodelground_interpolate_altitude(
    state,
    elevation,
    altitude,
    visibility_low,
    albedo,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  if (factor < 1e-6 || visibility_low >= (state->visibilities - 1))
  {
    return res_low;
  }

  double res_high = arpragueskymodelground_interpolate_altitude(
    state,
    elevation,
    altitude,
    visibility_low + 1,
    albedo,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  return arpragueskymodelground_lerp(res_low, res_high, factor);
}

double arpragueskymodelground_interpolate_albedo(
	const ArPragueSkyModelGroundState  * state,
	double                  elevation,
	double                  altitude,
	double                  visibility,
	double                  albedo,
	int                     wavelength,
	double                  gamma,
	double                  alpha,
	double                  theta,
	int                     gamma_segment,
	int                     alpha_segment,
	int                     theta_segment
)
{
  const int albedo_low = (int)albedo;
  const double factor = albedo - (double)albedo_low;

  double res_low = arpragueskymodelground_interpolate_visibility(
    state,
    elevation,
    altitude,
    visibility,
    albedo_low,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  if (factor < 1e-6 || albedo_low >= (state->albedos - 1))
  {
    return res_low;
  }

  double res_high = arpragueskymodelground_interpolate_visibility(
    state,
    elevation,
    altitude,
    visibility,
    albedo_low + 1,
    wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  return arpragueskymodelground_lerp(res_low, res_high, factor);
}

double arpragueskymodelground_interpolate_wavelength(
	const ArPragueSkyModelGroundState  * state,
	double                  elevation,
	double                  altitude,
	double                  visibility,
	double                  albedo,
	double                  wavelength,
	double                  gamma,
	double                  alpha,
	double                  theta,
	int                     gamma_segment,
	int                     alpha_segment,
	int                     theta_segment
)
{
  // Don't interpolate, use the bin it belongs to

  return arpragueskymodelground_interpolate_albedo(
    state,
    elevation,
    altitude,
    visibility,
    albedo,
    (int)wavelength,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);
}

double arpragueskymodelground_sky_radiance(
	const ArPragueSkyModelGroundState  * state,
	const double                   theta,
	const double                   gamma,
	const double                   shadow,
	const double                   wavelength
)
{
  // Translate parameter values to indices

  const double visibility_control = arpragueskymodelground_map_parameter(state->visibility, state->visibilities, state->visibility_vals);
  const double albedo_control     = arpragueskymodelground_map_parameter(state->albedo, state->albedos, state->albedo_vals);
  const double altitude_control   = arpragueskymodelground_map_parameter(0, state->altitudes, state->altitude_vals);
  const double elevation_control  = arpragueskymodelground_map_parameter(state->elevation * MATH_RAD_TO_DEG, state->elevations, state->elevation_vals);

  const double channel_control = (wavelength - state->channel_start) / state->channel_width;

  if ( channel_control >= state->channels || channel_control < 0.) return 0.;

  // Get params corresponding to the indices, reconstruct result and interpolate

  const double alpha = state->elevation < 0 ? shadow : theta;

  const int gamma_segment = arpragueskymodelground_find_segment(gamma, state->sun_nbreaks, state->sun_breaks);
  const int alpha_segment = arpragueskymodelground_find_segment(alpha, state->zenith_nbreaks, state->zenith_breaks);
  const int theta_segment = arpragueskymodelground_find_segment(theta, state->emph_nbreaks, state->emph_breaks);

  const double res = arpragueskymodelground_interpolate_wavelength(
    state,
    elevation_control,
    altitude_control,
    visibility_control,
    albedo_control,
    channel_control,
    gamma,
    alpha,
    theta,
    gamma_segment,
    alpha_segment,
    theta_segment);

  return res;
}


///////////////////////////////////////////////
// Solar radiance
///////////////////////////////////////////////


const double PSMG_SUN_RAD_START_WL = 310;
const double PSMG_SUN_RAD_INC_WL = 1;
const double PSMG_SUN_RAD_TABLE[] =
{
9829.41, 10184., 10262.6, 10375.7, 10276., 10179.3, 10156.6, 10750.7, 11134., 11463.6, 11860.4, 12246.2, 12524.4, 12780., 13187.4, 13632.4, 13985.9, 13658.3, 13377.4, 13358.3, 13239., 13119.8, 13096.2, 13184., 13243.5, 13018.4, 12990.4, 13159.1, 13230.8, 13258.6, 13209.9, 13343.2, 13404.8, 13305.4, 13496.3, 13979.1, 14153.8, 14188.4, 14122.7, 13825.4, 14033.3, 13914.1, 13837.4, 14117.2, 13982.3, 13864.5, 14118.4, 14545.7, 15029.3, 15615.3, 15923.5, 16134.8, 16574.5, 16509., 16336.5, 16146.6, 15965.1, 15798.6, 15899.8, 16125.4, 15854.3, 15986.7, 15739.7, 15319.1, 15121.5, 15220.2, 15041.2, 14917.7, 14487.8, 14011., 14165.7, 14189.5, 14540.7, 14797.5, 14641.5, 14761.6, 15153.7, 14791.8, 14907.6, 15667.4, 16313.5, 16917., 17570.5, 18758.1, 20250.6, 21048.1, 21626.1, 22811.6, 23577.2, 23982.6, 24062.1, 23917.9, 23914.1, 23923.2, 24052.6, 24228.6, 24360.8, 24629.6, 24774.8, 24648.3, 24666.5, 24938.6, 24926.3, 24693.1, 24613.5, 24631.7, 24569.8, 24391.5, 24245.7, 24084.4, 23713.7, 22985.4, 22766.6, 22818.9, 22834.3, 22737.9, 22791.6, 23086.3, 23377.7, 23461., 23935.5, 24661.7, 25086.9, 25520.1, 25824.3, 26198., 26350.2, 26375.4, 26731.2, 27250.4, 27616., 28145.3, 28405.9, 28406.8, 28466.2, 28521.5, 28783.8, 29025.1, 29082.6, 29081.3, 29043.1, 28918.9, 28871.6, 29049., 29152.5, 29163.2, 29143.4, 28962.7, 28847.9, 28854., 28808.7, 28624.1, 28544.2, 28461.4, 28411.1, 28478., 28469.8, 28513.3, 28586.5, 28628.6, 28751.5, 28948.9, 29051., 29049.6, 29061.7, 28945.7, 28672.8, 28241.5, 27903.2, 27737., 27590.9, 27505.6, 27270.2, 27076.2, 26929.1, 27018.2, 27206.8, 27677.2, 27939.9, 27923.9, 27899.2, 27725.4, 27608.4, 27599.4, 27614.6, 27432.4, 27460.4, 27392.4, 27272., 27299.1, 27266.8, 27386.5, 27595.9, 27586.9, 27504.8, 27480.6, 27329.8, 26968.4, 26676.3, 26344.7, 26182.5, 26026.3, 25900.3, 25842.9, 25885.4, 25986.5, 26034.5, 26063.5, 26216.9, 26511.4, 26672.7, 26828.5, 26901.8, 26861.5, 26865.4, 26774.2, 26855.8, 27087.1, 27181.3, 27183.1, 27059.8, 26834.9, 26724.3, 26759.6, 26725.9, 26724.6, 26634.5, 26618.5, 26560.1, 26518.7, 26595.3, 26703.2, 26712.7, 26733.9, 26744.3, 26764.4, 26753.2, 26692.7, 26682.7, 26588.1, 26478., 26433.7, 26380.7, 26372.9, 26343.3, 26274.7, 26162.3, 26160.5, 26210., 26251.2, 26297.9, 26228.9, 26222.3, 26269.7, 26295.6, 26317.9, 26357.5, 26376.1, 26342.4, 26303.5, 26276.7, 26349.2, 26390., 26371.6, 26346.7, 26327.6, 26274.2, 26247.3, 26228.7, 26152.1, 25910.3, 25833.2, 25746.5, 25654.3, 25562., 25458.8, 25438., 25399.1, 25324.3, 25350., 25514., 25464.9, 25398.5, 25295.2, 25270.2, 25268.4, 25240.6, 25184.9, 25149.6, 25123.9, 25080.3, 25027.9, 25012.3, 24977.9, 24852.6, 24756.4, 24663.5, 24483.6, 24398.6, 24362.6, 24325.1, 24341.7, 24288.7, 24284.2, 24257.3, 24178.8, 24097.6, 24175.6, 24175.7, 24139.7, 24088.1, 23983.2, 23902.7, 23822.4, 23796.2, 23796.9, 23814.5, 23765.5, 23703., 23642., 23592.6, 23552., 23514.6, 23473.5, 23431., 23389.3, 23340., 23275.1, 23187.3, 23069.5, 22967., 22925.3, 22908.9, 22882.5, 22825., 22715.4, 22535.5, 22267.1, 22029.4, 21941.6, 21919.5, 21878.8, 21825.6, 21766., 21728.9, 21743.2, 21827.1, 21998.7, 22159.4, 22210., 22187.2, 22127.2, 22056.2, 22000.2, 21945.9, 21880.2, 21817.1, 21770.3, 21724.3, 21663.2, 21603.3, 21560.4, 21519.8, 21466.2, 21401.6, 21327.7, 21254.2, 21190.7, 21133.6, 21079.3, 21024., 20963.7, 20905.5, 20856.6, 20816.6, 20785.2, 20746.7, 20685.3, 20617.8, 20561.1, 20500.4, 20421.2, 20333.4, 20247., 20175.3, 20131.4, 20103.2, 20078.5, 20046.8, 19997.2, 19952.9, 19937.2, 19930.8, 19914.4, 19880.8, 19823., 19753.8, 19685.9, 19615.3, 19537.5, 19456.8, 19377.6, 19309.4, 19261.9, 19228., 19200.5, 19179.5, 19164.8, 19153.1, 19140.6, 19129.2, 19120.6, 19104.5, 19070.6, 19023.9, 18969.3, 18911.4, 18855., 18798.6, 18740.8, 18672.7, 18585.2, 18501., 18442.4, 18397.5, 18353.9, 18313.2, 18276.8, 18248.3, 18231.2, 18224., 18225.4, 18220.1, 18192.6, 18155.1, 18119.8, 18081.6, 18035.6, 17987.4, 17942.8, 17901.7, 17864.2, 17831.1, 17802.9, 17771.5, 17728.6, 17669.7, 17590.1, 17509.5, 17447.4, 17396., 17347.4, 17300.3, 17253.2, 17206.1, 17159., 17127.6, 17127.6, 17133.6, 17120.4, 17097.2, 17073.3, 17043.7, 17003.4, 16966.3, 16946.3, 16930.9, 16907.7, 16882.7, 16862., 16837.8, 16802.1, 16759.2, 16713.6, 16661.8, 16600.8, 16542.6, 16499.4, 16458.7, 16408., 16360.6, 16329.5, 16307.4, 16286.7, 16264.9, 16239.6, 16207.8, 16166.8, 16118.2, 16064., 16011.2, 15966.9, 15931.9, 15906.9, 15889.1, 15875.5, 15861.2, 15841.3, 15813.1, 15774.2, 15728.8, 15681.4, 15630., 15572.9, 15516.5, 15467.2, 15423., 15381.6, 15354.4, 15353., 15357.3, 15347.3, 15320.2, 15273.1, 15222., 15183.1, 15149.6, 15114.6, 15076.8, 15034.6, 14992.9
};

double arpragueskymodelground_solar_radiance(
        const ArPragueSkyModelGroundState  * state,
        const double                   theta,		
        const double                   wavelength
        )
{
	const double wl_idx = (wavelength - PSMG_SUN_RAD_START_WL) / PSMG_SUN_RAD_INC_WL;
	double sun_radiance = 0.0;

	if (wl_idx >= 0.0)
	{
		const int wl_idx_low = floor(wl_idx);
		const double wl_idx_float = wl_idx - floor(wl_idx);
		sun_radiance = PSMG_SUN_RAD_TABLE[wl_idx_low] * (1.0 - wl_idx_float) + PSMG_SUN_RAD_TABLE[wl_idx_low + 1] * wl_idx_float;
	}

	const double tau = arpragueskymodelground_transmittance(
		state,
		theta,
		wavelength,
		MATH_HUGE_DOUBLE
	);

	return sun_radiance * tau;
}


///////////////////////////////////////////////
// Transmittance
///////////////////////////////////////////////


int arpragueskymodelground_circle_bounds_2D(
	double x_v,
	double y_v,
	double y_c,
	double radius,
	double *d
)
{
	double qa = (x_v * x_v) + (y_v * y_v);
	double qb = 2.0 * y_c * y_v;
	double qc = (y_c * y_c) - (radius * radius);
	double n = (qb * qb) - (4.0 * qa * qc);
	if (n <= 0)
	{
		return 0;
	}
	float d1;
	float d2;
	n = sqrt(n);
	d1 = (-qb + n) / (2.0 * qa);
	d2 = (-qb - n) / (2.0 * qa);
	*d = (d1 > 0 && d2 > 0) ? (d1 < d2 ? d1 : d2) : (d1 > d2 ? d1 : d2);
	if (*d <= 0)
	{
		return 0;
	}
	return 1;
}

void arpragueskymodelground_scaleAD(
	double x_p,
	double y_p,
	double *a,
	double *d
)
{
	double n;
	n = sqrt((x_p * x_p) + (y_p * y_p));
	*a = n - PSMG_PLANET_RADIUS;
	*a = *a > 0 ? *a : 0;
	*a = pow(*a / PSMG_ATMO_WIDTH, 1.0 / 3.0);
	*d = acos(y_p / n) * PSMG_PLANET_RADIUS;
	*d = *d / 1571524.413613; // Maximum distance to the edge of the atmosphere in the transmittance model
	*d = pow(*d, 0.25);
	*d = *d > 1.0 ? 1.0 : *d;
}

void arpragueskymodelground_toAD(
	double theta,
	double distance,
	double altitude,
	double *a,
	double *d
)
{
	// Ray circle intersection
	double x_v = sin(theta);
	double y_v = cos(theta);
	double x_c = 0;
	double y_c = PSMG_PLANET_RADIUS + altitude;
	double atmo_edge = PSMG_PLANET_RADIUS + PSMG_ATMO_WIDTH;
	double n;
        if (altitude < 0.001) // Handle altitudes close to 0 separately to avoid reporting intersections on the other side of the planet
	{
		if (theta <= 0.5 * MATH_PI)
		{
			if (arpragueskymodelground_circle_bounds_2D(x_v, y_v, y_c, atmo_edge, &n) == 0)
			{
				// Then we have a problem!
				// Return something, but this should never happen so long as the camera is inside the atmosphere
				// Which it should be in this work
				*a = 0;
				*d = 0;
				return;
			}
		}
		else
		{
			n = 0;
		}
	}
	else
	{
		if (arpragueskymodelground_circle_bounds_2D(x_v, y_v, y_c, PSMG_PLANET_RADIUS, &n) == 1) // Check for planet intersection
		{
			if (n <= distance) // We do intersect the planet so return a and d at the surface
			{
				double x_p = x_v * n;
				double y_p = (y_v * n) + PSMG_PLANET_RADIUS + altitude;
				arpragueskymodelground_scaleAD(x_p, y_p, a, d);
				return;
			}
		}
		if (arpragueskymodelground_circle_bounds_2D(x_v, y_v, y_c, atmo_edge, &n) == 0)
		{
			// Then we have a problem!
			// Return something, but this should never happen so long as the camera is inside the atmosphere
			// Which it should be in this work
			*a = 0;
			*d = 0;
			return;
		}
	}
	double distance_corrected = n;
	// Use the smaller of the distances
	distance_corrected = distance < distance_corrected ? distance : distance_corrected;
	// Points in world space
	double x_p = x_v * distance_corrected;
	double y_p = (y_v * distance_corrected) + PSMG_PLANET_RADIUS + altitude;
	arpragueskymodelground_scaleAD(x_p, y_p, a, d);
}

float *arpragueskymodelground_transmittance_coefs_index(
	const ArPragueSkyModelGroundState  * state,
	const int visibility,
	const int altitude,
	const int wavelength
)
{
	int transmittance_values_per_visibility = state->trans_rank * 11 * state->trans_altitudes;
	return &state->transmission_dataset_V[(visibility * transmittance_values_per_visibility) + (((altitude * 11) + wavelength) * state->trans_rank)];
}

void arpragueskymodelground_transmittance_interpolate_wavelength(
	const ArPragueSkyModelGroundState  * state,
	const int visibility,
	const int altitude,
	const int wavelength_low,
	const int wavelength_inc,
	const double wavelength_w,
	double *coefficients
)
{
	float *wll = arpragueskymodelground_transmittance_coefs_index(state, visibility, altitude, wavelength_low);
	float *wlu = arpragueskymodelground_transmittance_coefs_index(state, visibility, altitude, wavelength_low + wavelength_inc);
	for (int i = 0; i < state->trans_rank; i++)
	{
		coefficients[i] = arpragueskymodelground_lerp(wll[i], wlu[i], wavelength_w);
	}
}

double arpragueskymodelground_calc_transmittance_svd_altitude(
	const ArPragueSkyModelGroundState *state,
	const int visibility,
	const int altitude,
	const int wavelength_low,
	const int wavelength_inc,
	const double wavelength_factor,
	const int a_int,
	const int d_int,
	const int a_inc,
	const int d_inc,
	const double wa,
	const double wd)
{
	float t[4] = { 0.0, 0.0, 0.0, 0.0 };
	double interpolated_coefficients[12];
	arpragueskymodelground_transmittance_interpolate_wavelength(state, visibility, altitude, wavelength_low, wavelength_inc, wavelength_factor, interpolated_coefficients);
	int index = 0;
	// Calculate pow space values
	for (int al = a_int; al <= a_int + a_inc; al++)
	{
		for (int dl = d_int; dl <= d_int + d_inc; dl++)
		{
			for (int i = 0; i < state->trans_rank; i++)
			{
				t[index] = t[index] + (state->transmission_dataset_U[(altitude * state->trans_n_a * state->trans_n_d * state->trans_rank) + (((dl * state->trans_n_a) + al) * state->trans_rank) + i] * interpolated_coefficients[i]);
			}
			index++;
		}
	}
	if (d_inc == 1)
	{
		t[0] = arpragueskymodelground_lerp(t[0], t[1], wd);
		t[1] = arpragueskymodelground_lerp(t[2], t[3], wd);
	}
	if (a_inc == 1)
	{
		t[0] = arpragueskymodelground_lerp(t[0], t[1], wa);
	}
	return t[0];
}

double arpragueskymodelground_nonlinlerp(const double a, const double b, const double w, const double p)
{
	double c1 = pow(a, p);
	double c2 = pow(b, p);
	return ((pow(w, p) - c1) / (c2 - c1));
}

double arpragueskymodelground_calc_transmittance_svd(
	const ArPragueSkyModelGroundState *state,
	const double a,
	const double d,
	const int visibility,
	const int wavelength_low,
	const int wavelength_inc,
	const double wavelength_factor,
	const int altitude_low,
	const int altitude_inc,
	const double altitude_factor)
{
	float t[4] = { 0.0, 0.0, 0.0, 0.0 };
	int a_int = (int)floor(a * (double)state->trans_n_a);
	int d_int = (int)floor(d * (double)state->trans_n_d);
	int a_inc = 0;
	int d_inc = 0;
	double wa = (a * (double)state->trans_n_a) - (double)a_int;
	double wd = (d * (double)state->trans_n_d) - (double)d_int;
	if (a_int < (state->trans_n_a - 1))
	{
		a_inc = 1;
		wa = arpragueskymodelground_nonlinlerp((double)a_int / (double)state->trans_n_a, (double)(a_int + a_inc) / (double)state->trans_n_a, a, 3.0);
	} else
	{
		a_int = state->trans_n_a - 1;
		wa = 0;
	}
	if (d_int < (state->trans_n_d - 1))
	{
		d_inc = 1;
		wd = arpragueskymodelground_nonlinlerp((double)d_int / (double)state->trans_n_d, (double)(d_int + d_inc) / (double)state->trans_n_d, d, 4.0);
	} else
	{
		d_int = state->trans_n_d - 1;
		wd = 0;
	}
	wa = wa < 0 ? 0 : wa;
	wa = wa > 1.0 ? 1.0 : wa;
	wd = wd < 0 ? 0 : wd;
	wd = wd > 1.0 ? 1.0 : wd;
	double trans[2];
	trans[0] = arpragueskymodelground_calc_transmittance_svd_altitude(state, visibility, altitude_low, wavelength_low, wavelength_inc, wavelength_factor, a_int, d_int, a_inc, d_inc, wa, wd);
	if (altitude_inc == 1)
	{
		trans[1] = arpragueskymodelground_calc_transmittance_svd_altitude(state, visibility, altitude_low + altitude_inc, wavelength_low, wavelength_inc, wavelength_factor, a_int, d_int, a_inc, d_inc, wa, wd);
		trans[0] = arpragueskymodelground_lerp(trans[0], trans[1], altitude_factor);
	}
	return trans[0];
}

void arpragueskymodelground_find_in_array(const float *arr, const int arrLength, const double value, int *index, int *inc, double *w)
{
	*inc = 0;
	if (value <= arr[0])
	{
		*index = 0;
		*w = 1.0;
		return;
	}
	if (value >= arr[arrLength - 1])
	{
		*index = arrLength - 1;
		*w = 0;
		return;
	}
	for (int i = 1; i < arrLength; i++)
	{
		if (value < arr[i])
		{
			*index = i - 1;
			*inc = 1;
			*w = (value - arr[i - 1]) / (arr[i] - arr[i - 1]); // Assume linear
			return;
		}
	}
}

double arpragueskymodelground_transmittance(
	const ArPragueSkyModelGroundState  * state,
	const double                   theta,
	const double                   wavelength,
	const double                   distance
)
{	const double wavelength_norm = (wavelength - state->channel_start) / state->channel_width;
	if (wavelength_norm >= state->channels || wavelength_norm < 0.)
		return 0.;
	const int wavelength_low = (int)wavelength_norm;
	const double wavelength_factor = 0.0;
	const int wavelength_inc = wavelength_low < 10 ? 1 : 0;

	const int altitude_low = 0;
	const double altitude_factor = 0.0;
	const int altitude_inc = 0;

	int vis_low;
	double vis_factor;
	int vis_inc;
	arpragueskymodelground_find_in_array(state->transmission_visibilities, state->trans_visibilities, state->visibility, &vis_low, &vis_inc, &vis_factor);

	// Calculate normalized and non-linearly scaled position in the atmosphere
	double a;
	double d;
	arpragueskymodelground_toAD(theta, distance, 0, &a, &d);

        // Evaluate basis at low visibility
	double trans_low = arpragueskymodelground_calc_transmittance_svd(state, a, d, vis_low, wavelength_low, wavelength_inc, wavelength_factor, altitude_low, altitude_inc, altitude_factor);

        // Evaluate basis at high visibility
	double trans_high = arpragueskymodelground_calc_transmittance_svd(state, a, d, vis_low + vis_inc, wavelength_low, wavelength_inc, wavelength_factor, altitude_low, altitude_inc, altitude_factor);

	// Return interpolated transmittance values
	double trans = arpragueskymodelground_lerp(trans_low, trans_high, vis_factor);

	trans = (trans < 0 ? 0 : (trans > 1.0 ? 1.0 : trans));
	trans = trans * trans;

	return trans;
}
