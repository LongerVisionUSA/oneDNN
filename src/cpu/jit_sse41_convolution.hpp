/*******************************************************************************
* Copyright 2017-2020 Intel Corporation
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*******************************************************************************/

#ifndef CPU_JIT_SSE41_CONVOLUTION_HPP
#define CPU_JIT_SSE41_CONVOLUTION_HPP

#include "c_types_map.hpp"
#include "dnnl_thread.hpp"
#include "utils.hpp"

#include "cpu_convolution_pd.hpp"

#include "jit_primitive_conf.hpp"
#include "jit_sse41_conv_kernel_f32.hpp"
#include "primitive.hpp"

namespace dnnl {
namespace impl {
namespace cpu {

struct jit_sse41_convolution_fwd_t : public primitive_t {
    struct pd_t : public cpu_convolution_fwd_pd_t {
        pd_t(const convolution_desc_t *adesc, const primitive_attr_t *attr,
                const typename pd_t::base_class *hint_fwd_pd)
            : cpu_convolution_fwd_pd_t(adesc, attr, hint_fwd_pd), jcp_() {}

        DECLARE_COMMON_PD_T(JIT_IMPL_NAME_HELPER("jit:", sse41, ""),
                jit_sse41_convolution_fwd_t);

        status_t init(engine_t *engine) {
            bool ok = true && is_fwd()
                    && set_default_alg_kind(alg_kind::convolution_direct)
                    && expect_data_types(data_type::f32, data_type::f32,
                            data_type::f32, data_type::f32, data_type::f32)
                    && attr()->has_default_values(
                            primitive_attr_t::skip_mask_t::post_ops)
                    && !has_zero_dim_memory() && set_default_formats();
            if (!ok) return status::unimplemented;

            return jit_sse41_conv_fwd_kernel_f32::init_conf(jcp_, *desc(),
                    *src_md(), *weights_md(), *dst_md(), *attr(),
                    dnnl_get_max_threads());
        }

        jit_conv_conf_t jcp_;

    protected:
        bool set_default_formats() {
            using namespace format_tag;

            const bool flat = IC() == 3;
            auto src_tag = flat
                    ? utils::pick(ndims() - 3, ncw, nchw, ncdhw)
                    : utils::pick(ndims() - 3, nCw8c, nChw8c, nCdhw8c);
            auto dst_tag = utils::pick(ndims() - 3, nCw8c, nChw8c, nCdhw8c);
            auto wei_tag = with_groups()
                    ? utils::pick(2 * ndims() - 6 + flat, gOIw8i8o, gOwi8o,
                            gOIhw8i8o, gOhwi8o, gOIdhw8i8o, gOdhwi8o)
                    : utils::pick(2 * ndims() - 6 + flat, OIw8i8o, Owi8o,
                            OIhw8i8o, Ohwi8o, OIdhw8i8o, Odhwi8o);

            return set_default_formats_common(src_tag, wei_tag, dst_tag);
        }
    };

    jit_sse41_convolution_fwd_t(const pd_t *apd) : primitive_t(apd) {
        kernel_ = new jit_sse41_conv_fwd_kernel_f32(pd()->jcp_, *pd()->attr());
    }
    ~jit_sse41_convolution_fwd_t() { delete kernel_; };

    typedef typename prec_traits<data_type::f32>::type data_t;

    virtual status_t execute(const exec_ctx_t &ctx) const override {
        execute_forward(ctx);
        return status::success;
    }

private:
    void execute_forward(const exec_ctx_t &ctx) const;
    const pd_t *pd() const { return (const pd_t *)primitive_t::pd().get(); }
    jit_sse41_conv_fwd_kernel_f32 *kernel_;
};

} // namespace cpu
} // namespace impl
} // namespace dnnl

#endif